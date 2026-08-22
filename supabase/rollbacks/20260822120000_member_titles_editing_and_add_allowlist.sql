begin;

drop function if exists public.admin_add_allowlist_member(
  text, smallint, smallint, text, text, smallint, text, text[], text, text,
  boolean, boolean, text[], boolean
);

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
