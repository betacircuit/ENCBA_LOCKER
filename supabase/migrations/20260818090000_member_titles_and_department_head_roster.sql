begin;

-- leadership_role은 관리자/주장/매니저 권한과 직결된 컬럼이라 한 사람당 값 하나만
-- 가진다. 부서장·팀 내 직책처럼 권한과 무관하게 여러 개를 동시에 달 수 있는
-- 표시용 타이틀은 별도 배열 컬럼으로 둔다.
alter table public.member_allowlist
  add column if not exists titles text[] not null default '{}'::text[];
alter table public.profiles
  add column if not exists titles text[] not null default '{}'::text[];

create or replace function public.sync_reservation_role_on_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles as profile
  set is_reservation_manager = allowed.is_reservation_manager,
      department = allowed.department,
      is_freshman = allowed.is_freshman,
      titles = allowed.titles
  from public.member_allowlist as allowed
  where profile.id = new.id
    and allowed.consumed_by = new.id;
  return new;
end;
$$;

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
  department text,
  is_freshman boolean,
  titles text[]
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
    coalesce(nullif(profile.department, ''), allowed.department, ''),
    coalesce(profile.is_freshman, allowed.is_freshman, false),
    coalesce(nullif(profile.titles, '{}'::text[]), allowed.titles, '{}'::text[])
  from public.member_allowlist as allowed
  left join public.profiles as profile on profile.id = allowed.consumed_by
  where (select auth.uid()) is not null
    and (
      requested_status = 'all'
      or (requested_status = 'military'
          and coalesce(profile.membership_status, allowed.membership_status) = 'military_leave')
    )
    and (
      nullif(btrim(requested_query), '') is null
      or coalesce(profile.display_name, allowed.name) ilike '%' || btrim(requested_query) || '%'
      or lpad(coalesce(profile.student_year, allowed.student_year, 0)::text, 2, '0')
        = regexp_replace(requested_query, '[^0-9]', '', 'g')
    )
  order by coalesce(profile.display_name, allowed.name);
$$;

revoke all on function public.list_member_directory(text, text) from public, anon;
grant execute on function public.list_member_directory(text, text) to authenticated;

-- 부서장·BEN 팀 내 직책 배정. leadership_role(전체 동아리 권한)은 건드리지 않는다.
update public.member_allowlist
set department = '컴퓨터공학과', student_year = 25, titles = titles || array['밴드부장']
where login_name = '이민섭';

update public.member_allowlist
set department = '국어교육과', student_year = 24, titles = titles || array['연경/대회부장']
where login_name = '이승민';

update public.member_allowlist
set department = '첨단융합학부', student_year = 25,
    titles = titles || array['신입생부장', '벤 주장']
where login_name = '홍성준';

update public.member_allowlist
set titles = titles || array['벤 감독']
where login_name in ('유승준', '임준호', '시유상');

commit;

begin;

-- 새 enum 값은 이 트랜잭션 안에서는 쓸 수 없으므로(Postgres 제약),
-- 추가만 하고 이 파일 안에서 바로 사용하지 않는다.
alter type public.membership_status add value if not exists 'exchange_student';
alter type public.membership_status add value if not exists 'study_abroad';

commit;

begin;

-- exchange_student/study_abroad를 admin_update_member가 허용하고,
-- 프로필 배지(군복무/졸업과 같은 자리)에도 반영한다.
create or replace function public.admin_update_member(
  requested_directory_id text,
  requested_name text,
  requested_student_year smallint,
  requested_joined_year smallint,
  requested_phone text,
  requested_position text,
  requested_jersey_number smallint,
  requested_membership_status text,
  requested_team_codes text[],
  requested_leadership_role text,
  requested_active boolean,
  requested_department text default '',
  requested_reservation_manager boolean default false,
  requested_freshman boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile uuid;
  target_allowlist bigint;
  is_allowlist boolean := requested_directory_id like 'allowlist:%';
  current_department text;
  current_reservation_manager boolean;
begin
  if not public.is_encba_admin() then
    raise exception 'ENCBA_ADMIN_OR_CAPTAIN_REQUIRED';
  end if;
  if nullif(btrim(requested_name), '') is null
    or requested_student_year not between 0 and 99
    or requested_joined_year not between 1977 and 2100
    or requested_position not in ('PG', 'SG', 'SF', 'PF', 'C', '미정')
    or requested_jersey_number not between 0 and 99
    or requested_membership_status not in (
      'yb', 'ob', 'military_leave', 'graduated', 'inactive',
      'exchange_student', 'study_abroad'
    )
    or coalesce(requested_leadership_role, 'member') not in ('member', 'manager', 'captain', 'admin')
    or cardinality(requested_team_codes) < 1
    or not requested_team_codes <@ array['ENCBA', 'BEN']::text[] then
    raise exception 'ENCBA_INVALID_MEMBER_PROFILE';
  end if;

  if is_allowlist then
    target_allowlist := substring(requested_directory_id from 11)::bigint;
    select allowed.department, allowed.is_reservation_manager
      into current_department, current_reservation_manager
    from public.member_allowlist as allowed
    where allowed.id = target_allowlist;
  else
    target_profile := requested_directory_id::uuid;
    select profile.department, profile.is_reservation_manager
      into current_department, current_reservation_manager
    from public.profiles as profile
    where profile.id = target_profile;
  end if;

  -- 예약자 역할과 학과는 관리자 전용이다. 값이 바뀔 때만 막는다.
  if coalesce(requested_reservation_manager, false)
       is distinct from coalesce(current_reservation_manager, false)
     and not public.is_primary_encba_admin() then
    raise exception 'ENCBA_RESERVATION_ROLE_ADMIN_ONLY' using errcode = '42501';
  end if;
  if btrim(coalesce(requested_department, ''))
       is distinct from coalesce(current_department, '')
     and not public.is_primary_encba_admin() then
    raise exception 'ENCBA_DEPARTMENT_ADMIN_ONLY' using errcode = '42501';
  end if;

  if is_allowlist then
    update public.member_allowlist
    set name = btrim(requested_name),
        login_name = btrim(requested_name),
        student_year = requested_student_year,
        joined_year = requested_joined_year,
        phone = coalesce(requested_phone, ''),
        position = requested_position,
        jersey_number = requested_jersey_number,
        membership_status = requested_membership_status::public.membership_status,
        team_codes = requested_team_codes,
        leadership_role = coalesce(requested_leadership_role, 'member'),
        is_admin = coalesce(requested_leadership_role, 'member') = 'admin',
        is_schedule_manager = coalesce(requested_leadership_role, 'member') in ('admin', 'captain'),
        is_active = requested_active,
        department = btrim(coalesce(requested_department, '')),
        is_reservation_manager = coalesce(requested_reservation_manager, false),
        is_freshman = coalesce(requested_freshman, false)
    where id = target_allowlist;

    -- 이미 가입한 명단이면 프로필에도 같이 반영한다.
    update public.profiles as profile
    set department = btrim(coalesce(requested_department, '')),
        is_reservation_manager = coalesce(requested_reservation_manager, false),
        is_freshman = coalesce(requested_freshman, false)
    from public.member_allowlist as allowed
    where allowed.id = target_allowlist and profile.id = allowed.consumed_by;
    return;
  end if;

  update public.profiles
  set name = btrim(requested_name),
      display_name = btrim(requested_name),
      student_year = requested_student_year,
      joined_year = requested_joined_year,
      phone = coalesce(requested_phone, ''),
      position = requested_position,
      jersey_number = requested_jersey_number,
      membership_status = requested_membership_status::public.membership_status,
      leadership_role = coalesce(requested_leadership_role, 'member'),
      is_admin = coalesce(requested_leadership_role, 'member') = 'admin',
      is_schedule_manager = coalesce(requested_leadership_role, 'member') in ('admin', 'captain'),
      is_active = requested_active,
      department = btrim(coalesce(requested_department, '')),
      is_reservation_manager = coalesce(requested_reservation_manager, false),
      is_freshman = coalesce(requested_freshman, false),
      badge = case requested_membership_status
        when 'military_leave' then '군복무'
        when 'graduated' then '졸업'
        when 'exchange_student' then '교환학생'
        when 'study_abroad' then '유학'
        else null
      end
  where id = target_profile;

  delete from public.profile_teams where profile_id = target_profile;
  insert into public.profile_teams (profile_id, team_id)
  select target_profile, t.id from public.teams t
  where t.code = any(requested_team_codes);

  update public.member_allowlist
  set name = btrim(requested_name),
      login_name = btrim(requested_name),
      student_year = requested_student_year,
      joined_year = requested_joined_year,
      phone = coalesce(requested_phone, ''),
      position = requested_position,
      jersey_number = requested_jersey_number,
      membership_status = requested_membership_status::public.membership_status,
      team_codes = requested_team_codes,
      leadership_role = coalesce(requested_leadership_role, 'member'),
      is_admin = coalesce(requested_leadership_role, 'member') = 'admin',
      is_schedule_manager = coalesce(requested_leadership_role, 'member') in ('admin', 'captain'),
      is_active = requested_active,
      department = btrim(coalesce(requested_department, '')),
      is_reservation_manager = coalesce(requested_reservation_manager, false),
      is_freshman = coalesce(requested_freshman, false)
  where consumed_by = target_profile;
end;
$$;

revoke all on function public.admin_update_member(
  text, text, smallint, smallint, text, text, smallint, text, text[], text,
  boolean, text, boolean, boolean
) from public, anon;
grant execute on function public.admin_update_member(
  text, text, smallint, smallint, text, text, smallint, text, text[], text,
  boolean, text, boolean, boolean
) to authenticated;

commit;

-- 새 일정이 등록되면 공지처럼 실시간으로 알림을 띄우기 위해 events도
-- videos/announcements와 같은 방식으로 realtime publication에 추가한다.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'events'
  ) then
    alter publication supabase_realtime add table public.events;
  end if;
end $$;

alter table public.events replica identity full;
