begin;

-- 예약 담당은 직책과 별도로 여러 명에게 부여할 수 있다.
alter table public.member_allowlist
  add column if not exists is_reservation_manager boolean not null default false;
alter table public.profiles
  add column if not exists is_reservation_manager boolean not null default false;
alter table public.member_allowlist
  add column if not exists department text not null default ''
  check (char_length(department) <= 100);
alter table public.profiles
  add column if not exists department text not null default ''
  check (char_length(department) <= 100);

create index if not exists profiles_reservation_manager_active_idx
  on public.profiles (is_reservation_manager, is_active)
  where is_reservation_manager;

create or replace function public.sync_reservation_role_on_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles as profile
  set is_reservation_manager = allowed.is_reservation_manager,
      department = allowed.department
  from public.member_allowlist as allowed
  where profile.id = new.id
    and allowed.consumed_by = new.id;
  return new;
end;
$$;

drop trigger if exists profile_sync_reservation_role on public.profiles;
create trigger profile_sync_reservation_role
after insert on public.profiles
for each row execute function public.sync_reservation_role_on_profile_insert();

drop function if exists public.list_member_directory(text, text);
create function public.list_member_directory(
  requested_status text default 'all',
  requested_query text default ''
)
returns table (
  directory_id text,
  name text,
  student_year smallint,
  generation smallint,
  joined_year smallint,
  membership_status public.membership_status,
  is_active boolean,
  phone text,
  "position" text,
  jersey_number smallint,
  team_codes text[],
  leadership_role text,
  is_reservation_manager boolean,
  department text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(profile.id::text, 'allowlist:' || allowed.id::text),
    coalesce(profile.display_name, allowed.name),
    coalesce(profile.student_year, allowed.student_year),
    coalesce(profile.generation, allowed.generation, 1::smallint),
    coalesce(profile.joined_year, allowed.joined_year),
    coalesce(profile.membership_status, allowed.membership_status),
    coalesce(profile.is_active, allowed.is_active),
    coalesce(nullif(profile.phone, ''), allowed.phone, ''),
    coalesce(profile.position, allowed.position, '미정'),
    coalesce(profile.jersey_number, allowed.jersey_number, 0::smallint),
    case
      when profile.id is null then coalesce(allowed.team_codes, array['ENCBA']::text[])
      else array(
        select team.code
        from public.profile_teams as membership
        join public.teams as team on team.id = membership.team_id
        where membership.profile_id = profile.id
        order by team.code
      )
    end,
    coalesce(profile.leadership_role, allowed.leadership_role, 'member'),
    coalesce(profile.is_reservation_manager, allowed.is_reservation_manager, false),
    coalesce(nullif(profile.department, ''), allowed.department, '')
  from public.member_allowlist as allowed
  left join public.profiles as profile on profile.id = allowed.consumed_by
  where (select auth.uid()) is not null
    and (
      requested_status = 'all'
      or (
        requested_status = 'military'
        and coalesce(profile.membership_status, allowed.membership_status) = 'military_leave'
      )
    )
    and (
      nullif(btrim(requested_query), '') is null
      or coalesce(profile.display_name, allowed.name) ilike '%' || btrim(requested_query) || '%'
      or lpad(coalesce(profile.student_year, allowed.student_year, 0)::text, 2, '0')
        = regexp_replace(requested_query, '[^0-9]', '', 'g')
    )
  order by coalesce(profile.student_year, allowed.student_year, 0),
           coalesce(profile.display_name, allowed.name);
$$;

revoke all on function public.list_member_directory(text, text) from public, anon;
grant execute on function public.list_member_directory(text, text) to authenticated;

create or replace function public.set_member_reservation_manager(
  requested_directory_id text,
  requested_value boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_id uuid;
  allowlist_id bigint;
begin
  if not public.is_encba_admin() then
    raise exception '관리자만 예약자 역할을 변경할 수 있습니다.' using errcode = '42501';
  end if;

  if requested_directory_id like 'allowlist:%' then
    allowlist_id := substring(requested_directory_id from 11)::bigint;
    update public.member_allowlist
    set is_reservation_manager = requested_value
    where id = allowlist_id;

    update public.profiles as profile
    set is_reservation_manager = requested_value
    from public.member_allowlist as allowed
    where allowed.id = allowlist_id
      and profile.id = allowed.consumed_by;
  else
    profile_id := requested_directory_id::uuid;
    update public.profiles
    set is_reservation_manager = requested_value
    where id = profile_id;
    update public.member_allowlist
    set is_reservation_manager = requested_value
    where consumed_by = profile_id;
  end if;
end;
$$;

revoke all on function public.set_member_reservation_manager(text, boolean) from public, anon;
grant execute on function public.set_member_reservation_manager(text, boolean) to authenticated;

-- 명단 원본의 학과까지 관리자 편집에 포함한다. 기존 호출 서명은 호환용으로 유지된다.
create or replace function public.set_member_department(
  requested_directory_id text,
  requested_department text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_id uuid;
  allowlist_id bigint;
begin
  if not public.is_encba_admin() then
    raise exception '관리자만 학과 정보를 변경할 수 있습니다.' using errcode = '42501';
  end if;
  if char_length(coalesce(requested_department, '')) > 100 then
    raise exception '학과 정보가 너무 깁니다.' using errcode = '22023';
  end if;

  if requested_directory_id like 'allowlist:%' then
    allowlist_id := substring(requested_directory_id from 11)::bigint;
    update public.member_allowlist
    set department = btrim(coalesce(requested_department, ''))
    where id = allowlist_id;
    update public.profiles as profile
    set department = btrim(coalesce(requested_department, ''))
    from public.member_allowlist as allowed
    where allowed.id = allowlist_id and profile.id = allowed.consumed_by;
  else
    profile_id := requested_directory_id::uuid;
    update public.profiles
    set department = btrim(coalesce(requested_department, ''))
    where id = profile_id;
    update public.member_allowlist
    set department = btrim(coalesce(requested_department, ''))
    where consumed_by = profile_id;
  end if;
end;
$$;

revoke all on function public.set_member_department(text, text) from public, anon;
grant execute on function public.set_member_department(text, text) to authenticated;

-- 경기의 주전은 순서를 유지하고, 프로필 삭제 시 자동 정리한다.
create table if not exists public.event_starters (
  event_id uuid not null references public.events(id) on delete cascade,
  allowlist_id bigint not null references public.member_allowlist(id) on delete cascade,
  sort_order smallint not null check (sort_order between 0 and 20),
  created_at timestamptz not null default now(),
  primary key (event_id, allowlist_id),
  unique (event_id, sort_order)
);

create index if not exists event_starters_allowlist_idx
  on public.event_starters (allowlist_id, event_id);

alter table public.event_starters enable row level security;
drop policy if exists event_starters_read on public.event_starters;
create policy event_starters_read on public.event_starters
for select to authenticated
using ((select public.can_access_event(event_id)));
drop policy if exists event_starters_manage on public.event_starters;
create policy event_starters_manage on public.event_starters
for all to authenticated
using ((select public.can_manage_schedule()))
with check ((select public.can_manage_schedule()));

revoke all on table public.event_starters from public, anon;
grant select, insert, update, delete on table public.event_starters to authenticated;

create or replace function public.replace_event_starters(
  requested_event_id uuid,
  requested_directory_ids text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_count integer;
begin
  if not public.can_manage_schedule() then
    raise exception '일정 관리자만 주전을 지정할 수 있습니다.' using errcode = '42501';
  end if;
  if coalesce(cardinality(requested_directory_ids), 0) > 12 then
    raise exception '주전은 최대 12명까지 지정할 수 있습니다.' using errcode = '22023';
  end if;

  with requested as (
    select value, ordinal::smallint - 1 as sort_order
    from unnest(coalesce(requested_directory_ids, '{}'::text[]))
      with ordinality as item(value, ordinal)
  ), resolved as (
    select distinct on (allowed.id)
      allowed.id as allowlist_id,
      requested.sort_order
    from requested
    join public.member_allowlist as allowed on allowed.id = case
      when requested.value like 'allowlist:%'
        then substring(requested.value from 11)::bigint
      when requested.value ~* '^[0-9a-f-]{36}$'
        then (select match.id from public.member_allowlist as match
              where match.consumed_by = requested.value::uuid limit 1)
      else null
    end
    order by allowed.id, requested.sort_order
  )
  select count(*) into resolved_count from resolved;

  if resolved_count <> coalesce(cardinality(requested_directory_ids), 0) then
    raise exception '선택한 주전 중 명단에서 찾을 수 없는 부원이 있습니다.' using errcode = '22023';
  end if;

  delete from public.event_starters where event_id = requested_event_id;

  insert into public.event_starters (event_id, allowlist_id, sort_order)
  select requested_event_id, allowed.id, requested.sort_order
  from (
    select value, ordinal::smallint - 1 as sort_order
    from unnest(coalesce(requested_directory_ids, '{}'::text[]))
      with ordinality as item(value, ordinal)
  ) as requested
  join public.member_allowlist as allowed on allowed.id = case
    when requested.value like 'allowlist:%'
      then substring(requested.value from 11)::bigint
    else (select match.id from public.member_allowlist as match
          where match.consumed_by = requested.value::uuid limit 1)
  end
  order by requested.sort_order;
end;
$$;

create or replace function public.list_event_starters(requested_event_ids uuid[])
returns table (
  event_id uuid,
  directory_id text,
  name text,
  sort_order smallint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    starter.event_id,
    coalesce(profile.id::text, 'allowlist:' || allowed.id::text),
    coalesce(profile.display_name, allowed.name),
    starter.sort_order
  from public.event_starters as starter
  join public.member_allowlist as allowed on allowed.id = starter.allowlist_id
  left join public.profiles as profile on profile.id = allowed.consumed_by
  where starter.event_id = any(coalesce(requested_event_ids, '{}'::uuid[]))
    and public.can_access_event(starter.event_id)
  order by starter.event_id, starter.sort_order;
$$;

revoke all on function public.replace_event_starters(uuid, text[]) from public, anon;
grant execute on function public.replace_event_starters(uuid, text[]) to authenticated;
revoke all on function public.list_event_starters(uuid[]) from public, anon;
grant execute on function public.list_event_starters(uuid[]) to authenticated;

-- 전술판은 해당 일정을 볼 수 있는 부원들이 함께 작성한다.
create table if not exists public.event_strategies (
  event_id uuid primary key references public.events(id) on delete cascade,
  offense text not null default '' check (char_length(offense) <= 3000),
  defense text not null default '' check (char_length(defense) <= 3000),
  notes text not null default '' check (char_length(notes) <= 3000),
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.event_strategies enable row level security;
drop policy if exists event_strategies_read on public.event_strategies;
create policy event_strategies_read on public.event_strategies
for select to authenticated
using ((select public.can_access_event(event_id)));
drop policy if exists event_strategies_insert on public.event_strategies;
create policy event_strategies_insert on public.event_strategies
for insert to authenticated
with check (
  updated_by = (select auth.uid())
  and (select public.can_access_event(event_id))
);
drop policy if exists event_strategies_update on public.event_strategies;
create policy event_strategies_update on public.event_strategies
for update to authenticated
using ((select public.can_access_event(event_id)))
with check (
  updated_by = (select auth.uid())
  and (select public.can_access_event(event_id))
);

drop trigger if exists event_strategies_set_updated_at on public.event_strategies;
create trigger event_strategies_set_updated_at
before update on public.event_strategies
for each row execute function public.set_updated_at();

revoke all on table public.event_strategies from public, anon;
grant select, insert, update on table public.event_strategies to authenticated;

create or replace function public.get_server_time()
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$
  select statement_timestamp();
$$;

revoke all on function public.get_server_time() from public, anon;
grant execute on function public.get_server_time() to authenticated;

-- 2026 선수 명단의 검증 가능한 항목만 반영한다. 매니저 행과 명단에 없는 신입생은 건드리지 않는다.
with roster(name, student_year, department, jersey_number, team_codes) as (
  values
    ('하승윤', 20::smallint, '조선해양공학과', 65::smallint, array['ENCBA']::text[]),
    ('용승현', 20::smallint, '전기정보공학부', 17::smallint, array['ENCBA']::text[]),
    ('김창래', 21::smallint, '전기정보공학부', 64::smallint, array['ENCBA']::text[]),
    ('김건오', 21::smallint, '화학생물공학부', 92::smallint, array['ENCBA']::text[]),
    ('나윤석', 21::smallint, '전기정보공학부', 56::smallint, array['ENCBA']::text[]),
    ('민영웅', 21::smallint, '산업공학과', 3::smallint, array['ENCBA','BEN']::text[]),
    ('시유상', 22::smallint, '자유전공학부', 63::smallint, null::text[]),
    ('정유석', 22::smallint, '기계공학부', 71::smallint, null::text[]),
    ('이영서', 23::smallint, '기계공학부', 58::smallint, null::text[]),
    ('임준호', 23::smallint, '자유전공학부', 8::smallint, array['ENCBA']::text[]),
    ('김창용', 23::smallint, '산업공학과', 72::smallint, array['ENCBA','BEN']::text[]),
    ('유승준', 23::smallint, '재료공학부', 25::smallint, array['ENCBA']::text[]),
    ('정민혁', 23::smallint, '재료공학부', 91::smallint, array['ENCBA']::text[]),
    ('이승민', 24::smallint, '국어교육과', 0::smallint, array['ENCBA']::text[]),
    ('황재문', 24::smallint, '전기정보공학부', 66::smallint, array['BEN']::text[]),
    ('유시현', 24::smallint, '기계공학부', 68::smallint, array['BEN']::text[]),
    ('방준모', 24::smallint, '첨단융합학부', 76::smallint, array['BEN']::text[]),
    ('김재룡', 24::smallint, '의류학과', null::smallint, array['BEN']::text[]),
    ('김연준', 25::smallint, '원자핵공학과', 27::smallint, array['BEN']::text[]),
    ('김지원', 25::smallint, '원자핵공학과', 19::smallint, array['BEN']::text[]),
    ('박서연', 22::smallint, '컴퓨터공학부', 93::smallint, array['BEN']::text[]),
    ('이민섭', 25::smallint, '컴퓨터공학부', 12::smallint, array['BEN']::text[]),
    ('이우진', 25::smallint, '전기정보공학부', 98::smallint, array['BEN']::text[]),
    ('최재원', 25::smallint, '전기정보공학부', 77::smallint, array['BEN']::text[]),
    ('홍성준', 25::smallint, '첨단융합학부', 2::smallint, array['BEN']::text[])
)
update public.member_allowlist as allowed
set student_year = roster.student_year,
    department = roster.department,
    jersey_number = coalesce(roster.jersey_number, allowed.jersey_number),
    team_codes = coalesce(roster.team_codes, allowed.team_codes)
from roster
where allowed.name = roster.name;

with roster(name, student_year, department, jersey_number, team_codes) as (
  values
    ('하승윤',20::smallint,'조선해양공학과',65::smallint,array['ENCBA']::text[]),
    ('용승현',20::smallint,'전기정보공학부',17::smallint,array['ENCBA']::text[]),
    ('김창래',21::smallint,'전기정보공학부',64::smallint,array['ENCBA']::text[]),
    ('김건오',21::smallint,'화학생물공학부',92::smallint,array['ENCBA']::text[]),
    ('나윤석',21::smallint,'전기정보공학부',56::smallint,array['ENCBA']::text[]),
    ('민영웅',21::smallint,'산업공학과',3::smallint,array['ENCBA','BEN']::text[]),
    ('시유상',22::smallint,'자유전공학부',63::smallint,null::text[]),
    ('정유석',22::smallint,'기계공학부',71::smallint,null::text[]),
    ('이영서',23::smallint,'기계공학부',58::smallint,null::text[]),
    ('임준호',23::smallint,'자유전공학부',8::smallint,array['ENCBA']::text[]),
    ('김창용',23::smallint,'산업공학과',72::smallint,array['ENCBA','BEN']::text[]),
    ('유승준',23::smallint,'재료공학부',25::smallint,array['ENCBA']::text[]),
    ('정민혁',23::smallint,'재료공학부',91::smallint,array['ENCBA']::text[]),
    ('이승민',24::smallint,'국어교육과',0::smallint,array['ENCBA']::text[]),
    ('황재문',24::smallint,'전기정보공학부',66::smallint,array['BEN']::text[]),
    ('유시현',24::smallint,'기계공학부',68::smallint,array['BEN']::text[]),
    ('방준모',24::smallint,'첨단융합학부',76::smallint,array['BEN']::text[]),
    ('김재룡',24::smallint,'의류학과',null::smallint,array['BEN']::text[]),
    ('김연준',25::smallint,'원자핵공학과',27::smallint,array['BEN']::text[]),
    ('김지원',25::smallint,'원자핵공학과',19::smallint,array['BEN']::text[]),
    ('박서연',22::smallint,'컴퓨터공학부',93::smallint,array['BEN']::text[]),
    ('이민섭',25::smallint,'컴퓨터공학부',12::smallint,array['BEN']::text[]),
    ('이우진',25::smallint,'전기정보공학부',98::smallint,array['BEN']::text[]),
    ('최재원',25::smallint,'전기정보공학부',77::smallint,array['BEN']::text[]),
    ('홍성준',25::smallint,'첨단융합학부',2::smallint,array['BEN']::text[])
)
update public.profiles as profile
set student_year = roster.student_year,
    department = roster.department,
    jersey_number = coalesce(roster.jersey_number, profile.jersey_number)
from roster, public.member_allowlist as allowed
where allowed.name = roster.name
  and profile.id = allowed.consumed_by;

delete from public.profile_teams as membership
using public.member_allowlist as allowed
where membership.profile_id = allowed.consumed_by
  and allowed.name in (
    '하승윤','용승현','김창래','김건오','나윤석','민영웅','임준호','김창용',
    '유승준','정민혁','이승민','황재문','유시현','방준모','김재룡','김연준',
    '김지원','박서연','이민섭','이우진','최재원','홍성준'
  );

insert into public.profile_teams (profile_id, team_id)
select allowed.consumed_by, team.id
from public.member_allowlist as allowed
cross join lateral unnest(allowed.team_codes) as code(value)
join public.teams as team on team.code = code.value
where allowed.consumed_by is not null
  and allowed.name in (
    '하승윤','용승현','김창래','김건오','나윤석','민영웅','임준호','김창용',
    '유승준','정민혁','이승민','황재문','유시현','방준모','김재룡','김연준',
    '김지원','박서연','이민섭','이우진','최재원','홍성준'
  )
on conflict do nothing;

commit;
