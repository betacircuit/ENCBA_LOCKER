begin;

-- titles(벤 감독 등 표시용 다중 직책)는 지금까지 화면에 보여주기만 하고 고칠 방법이
-- 없었다. admin_update_member에 편집 가능한 파라미터로 추가한다. 기존 서명 끝에
-- 기본값 있는 파라미터를 붙이는 것이라 예전 호출도 그대로 동작한다.
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
  requested_freshman boolean default false,
  requested_titles text[] default '{}'::text[]
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
        is_freshman = coalesce(requested_freshman, false),
        titles = coalesce(requested_titles, '{}'::text[])
    where id = target_allowlist;

    -- 이미 가입한 명단이면 프로필에도 같이 반영한다.
    update public.profiles as profile
    set department = btrim(coalesce(requested_department, '')),
        is_reservation_manager = coalesce(requested_reservation_manager, false),
        is_freshman = coalesce(requested_freshman, false),
        titles = coalesce(requested_titles, '{}'::text[])
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
      titles = coalesce(requested_titles, '{}'::text[]),
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
      is_freshman = coalesce(requested_freshman, false),
      titles = coalesce(requested_titles, '{}'::text[])
  where consumed_by = target_profile;
end;
$$;

revoke all on function public.admin_update_member(
  text, text, smallint, smallint, text, text, smallint, text, text[], text,
  boolean, text, boolean, boolean, text[]
) from public, anon;
grant execute on function public.admin_update_member(
  text, text, smallint, smallint, text, text, smallint, text, text[], text,
  boolean, text, boolean, boolean, text[]
) to authenticated;

-- 구글 로그인 때 실명을 대조하는 가입 명단(member_allowlist)에 아직 아무도 만든 적
-- 없는 신규 인원을 admin/captain이 직접 추가한다. 지금까지는 SQL로만 넣을 수 있었다.
create or replace function public.admin_add_allowlist_member(
  requested_name text,
  requested_student_year smallint,
  requested_joined_year smallint,
  requested_phone text,
  requested_position text,
  requested_jersey_number smallint,
  requested_membership_status text,
  requested_team_codes text[],
  requested_leadership_role text,
  requested_department text default '',
  requested_reservation_manager boolean default false,
  requested_freshman boolean default false,
  requested_titles text[] default '{}'::text[],
  requested_active boolean default true
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_id bigint;
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
  if coalesce(requested_reservation_manager, false) and not public.is_primary_encba_admin() then
    raise exception 'ENCBA_RESERVATION_ROLE_ADMIN_ONLY' using errcode = '42501';
  end if;

  insert into public.member_allowlist (
    login_name, name, student_year, generation, joined_year,
    membership_status, is_admin, is_schedule_manager, team_codes,
    phone, position, jersey_number, leadership_role,
    department, is_reservation_manager, is_freshman, titles, is_active
  ) values (
    btrim(requested_name), btrim(requested_name), requested_student_year, 1, requested_joined_year,
    requested_membership_status::public.membership_status,
    coalesce(requested_leadership_role, 'member') = 'admin',
    coalesce(requested_leadership_role, 'member') in ('admin', 'captain'),
    requested_team_codes,
    coalesce(requested_phone, ''), requested_position, requested_jersey_number,
    coalesce(requested_leadership_role, 'member'),
    btrim(coalesce(requested_department, '')), coalesce(requested_reservation_manager, false),
    coalesce(requested_freshman, false), coalesce(requested_titles, '{}'::text[]),
    coalesce(requested_active, true)
  )
  returning id into new_id;

  return new_id;
end;
$$;

revoke all on function public.admin_add_allowlist_member(
  text, smallint, smallint, text, text, smallint, text, text[], text, text,
  boolean, boolean, text[], boolean
) from public, anon;
grant execute on function public.admin_add_allowlist_member(
  text, smallint, smallint, text, text, smallint, text, text[], text, text,
  boolean, boolean, text[], boolean
) to authenticated;

notify pgrst, 'reload schema';

commit;
