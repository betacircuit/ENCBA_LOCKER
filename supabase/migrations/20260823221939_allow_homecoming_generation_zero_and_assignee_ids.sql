begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- 00학번은 2000학번을 뜻하는 정상 값이다. 새 제약을 먼저 검증한 뒤 기존
-- 제약을 제거해 배포 중에도 검증 공백이 생기지 않게 한다.
alter table public.homecoming_contacts
  add constraint homecoming_contacts_generation_range_check
  check (generation between 0 and 200) not valid;

alter table public.homecoming_contacts
  validate constraint homecoming_contacts_generation_range_check;

alter table public.homecoming_contacts
  drop constraint if exists homecoming_contacts_generation_check;

-- 기존의 짧은 담당자 이름은 활성 계정의 전체 이름과 유일하게 일치할 때만
-- 자동 연결한다. 동명이인처럼 후보가 여러 명이면 추측하지 않는다.
with raw_matches as (
  select
    contact.id as contact_id,
    profile.id as profile_id,
    profile.name as profile_name,
    case
      when replace(profile.name, ' ', '') =
        replace(btrim(contact.assigned_to_name), ' ', '') then 0
      else 1
    end as match_priority
  from public.homecoming_contacts contact
  join public.profiles profile
    on profile.is_active
   and replace(profile.name, ' ', '') like
     '%' || replace(btrim(contact.assigned_to_name), ' ', '')
  where contact.assigned_to is null
    and nullif(btrim(contact.assigned_to_name), '') is not null
), preferred_matches as (
  select *, min(match_priority) over (partition by contact_id) as best_priority
  from raw_matches
), candidate_matches as (
  select *, count(*) over (partition by contact_id) as match_count
  from preferred_matches
  where match_priority = best_priority
), unique_matches as (
  select contact_id, profile_id, profile_name
  from candidate_matches
  where match_count = 1
)
update public.homecoming_contacts contact
set assigned_to = matched.profile_id,
    assigned_to_name = matched.profile_name
from unique_matches matched
where contact.id = matched.contact_id;

-- 이미 ID가 있는 행의 표시 이름도 profiles의 전체 이름으로 정규화한다.
update public.homecoming_contacts contact
set assigned_to_name = profile.name
from public.profiles profile
where contact.assigned_to = profile.id
  and contact.assigned_to_name is distinct from profile.name;

-- 유일하게 확인할 수 없는 별칭은 잘못된 사람에게 배정하지 않고 미지정 처리한다.
update public.homecoming_contacts
set assigned_to_name = null
where assigned_to is null
  and assigned_to_name is not null;

create or replace function public.import_homecoming_contacts(
  requested_campaign_id uuid,
  requested_file_name text,
  requested_contacts jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  imported_count integer;
  missing_phone_count integer;
  unmatched_assignee_count integer;
begin
  if caller_id is null or not (select public.is_encba_admin()) then
    raise exception '관리자만 홈커밍 연락망을 가져올 수 있습니다.'
      using errcode = '42501';
  end if;

  if nullif(btrim(requested_file_name), '') is null
    or char_length(requested_file_name) > 255
    or jsonb_typeof(requested_contacts) <> 'array'
    or jsonb_array_length(requested_contacts) not between 1 and 1000
  then
    raise exception '홈커밍 파일명 또는 연락망 형식이 올바르지 않습니다.'
      using errcode = '22023';
  end if;

  perform 1
  from public.homecoming_campaigns campaign
  where campaign.id = requested_campaign_id
  for update;
  if not found then
    raise exception '홈커밍 캠페인을 찾지 못했습니다.'
      using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(requested_contacts) item
    where jsonb_typeof(item) <> 'object'
      or nullif(btrim(item ->> 'senior_name'), '') is null
      or char_length(btrim(item ->> 'senior_name')) > 80
      or char_length(coalesce(item ->> 'phone', '')) > 40
      or char_length(coalesce(item ->> 'home_or_office_phone', '')) > 40
      or char_length(coalesce(item ->> 'assigned_to_name', '')) > 80
      or char_length(coalesce(item ->> 'source_reference', '')) > 255
      or char_length(coalesce(item ->> 'notes', '')) > 4000
      or coalesce(item ->> 'contact_status', 'pending') not in (
        'pending', 'contacted', 'confirmed', 'declined'
      )
      or (
        item ->> 'generation' is not null
        and (
          item ->> 'generation' !~ '^[0-9]{1,3}$'
          or case
            when item ->> 'generation' ~ '^[0-9]{1,3}$'
              then (item ->> 'generation')::integer not between 0 and 200
            else true
          end
        )
      )
      or (
        item ->> 'assigned_to_id' is not null
        and (
          item ->> 'assigned_to_id' !~
            '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
          or case
            when item ->> 'assigned_to_id' ~
              '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
              then not exists (
                select 1
                from public.profiles profile
                where profile.id = (item ->> 'assigned_to_id')::uuid
              )
            else true
          end
        )
      )
      or (
        item ->> 'source_row' is not null
        and (
          item ->> 'source_row' !~ '^[0-9]+$'
          or case
            when item ->> 'source_row' ~ '^[0-9]+$'
              then (item ->> 'source_row')::integer < 1
            else true
          end
        )
      )
      or (
        item ? 'parking_required'
        and jsonb_typeof(item -> 'parking_required') not in ('boolean', 'null')
      )
  ) then
    raise exception '홈커밍 연락망에 저장할 수 없는 행이 있습니다.'
      using errcode = '22023';
  end if;

  delete from public.homecoming_contacts contact
  where contact.campaign_id = requested_campaign_id;

  with source_rows as (
    select
      (item ->> 'source_row')::integer as source_row,
      btrim(item ->> 'senior_name') as senior_name,
      (item ->> 'generation')::smallint as generation,
      nullif(btrim(item ->> 'home_or_office_phone'), '') as home_or_office_phone,
      coalesce(btrim(item ->> 'phone'), '') as phone,
      case
        when item ->> 'assigned_to_id' is null then null
        else (item ->> 'assigned_to_id')::uuid
      end as assigned_to_id,
      nullif(btrim(item ->> 'assigned_to_name'), '') as assigned_to_name,
      coalesce(item ->> 'contact_status', 'pending') as contact_status,
      (item ->> 'parking_required')::boolean as parking_required,
      nullif(btrim(item ->> 'source_reference'), '') as source_reference,
      nullif(btrim(item ->> 'notes'), '') as notes
    from jsonb_array_elements(requested_contacts) item
  ), inserted as (
    insert into public.homecoming_contacts (
      campaign_id,
      source_row,
      senior_name,
      generation,
      home_or_office_phone,
      phone,
      assigned_to,
      assigned_to_name,
      contact_status,
      parking_required,
      source_reference,
      notes
    )
    select
      requested_campaign_id,
      source.source_row,
      source.senior_name,
      source.generation,
      source.home_or_office_phone,
      source.phone,
      resolved.id,
      resolved.name,
      source.contact_status,
      source.parking_required,
      source.source_reference,
      source.notes
    from source_rows source
    left join lateral (
      select profile.id, profile.name
      from public.profiles profile
      where profile.id = source.assigned_to_id
        or (
          source.assigned_to_id is null
          and profile.name = source.assigned_to_name
          and (
            select count(*)
            from public.profiles same_name
            where same_name.name = source.assigned_to_name
          ) = 1
        )
      order by profile.is_active desc, profile.created_at
      limit 1
    ) resolved on true
    returning phone, home_or_office_phone, assigned_to, assigned_to_name
  )
  select
    count(*)::integer,
    count(*) filter (
      where nullif(phone, '') is null and home_or_office_phone is null
    )::integer,
    count(*) filter (
      where assigned_to_name is not null and assigned_to is null
    )::integer
  into imported_count, missing_phone_count, unmatched_assignee_count
  from inserted;

  update public.homecoming_campaigns
  set source_file_name = requested_file_name
  where id = requested_campaign_id;

  return jsonb_build_object(
    'imported', imported_count,
    'missing_phones', missing_phone_count,
    'unmatched_assignees', unmatched_assignee_count
  );
end;
$$;

revoke all on function public.import_homecoming_contacts(uuid, text, jsonb)
  from public, anon;
grant execute on function public.import_homecoming_contacts(uuid, text, jsonb)
  to authenticated;

notify pgrst, 'reload schema';

commit;
