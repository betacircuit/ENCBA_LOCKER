begin;

-- 연락망 교체를 한 트랜잭션에서 수행해 삭제 뒤 일부 행만 남는 상태를 막는다.
create function public.import_homecoming_contacts(
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
              then (item ->> 'generation')::integer not between 1 and 200
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
      nullif(btrim(item ->> 'assigned_to_name'), '') as assigned_to_name,
      coalesce(item ->> 'contact_status', 'pending') as contact_status,
      (item ->> 'parking_required')::boolean as parking_required,
      nullif(btrim(item ->> 'source_reference'), '') as source_reference,
      nullif(btrim(item ->> 'notes'), '') as notes
    from jsonb_array_elements(requested_contacts) item
  ),
  inserted as (
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
      (
        select profile.id
        from public.profiles profile
        where profile.name = source.assigned_to_name
        order by profile.is_active desc, profile.created_at
        limit 1
      ),
      source.assigned_to_name,
      source.contact_status,
      source.parking_required,
      source.source_reference,
      source.notes
    from source_rows source
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

commit;
