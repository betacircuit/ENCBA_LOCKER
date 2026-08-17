begin;

-- 20260817030000_atomic_admin_update_member.sql 되돌리기.
-- 14인자 함수를 지우고 20260812175729의 11인자 정의를 복원한다.
-- 예약자·학과·신입생은 다시 set_member_* 함수가 담당한다.

drop function if exists public.admin_update_member(
  text, text, smallint, smallint, text, text, smallint, text, text[], text,
  boolean, text, boolean, boolean
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
  requested_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile uuid;
begin
  if not public.is_encba_admin() then
    raise exception 'ENCBA_ADMIN_OR_CAPTAIN_REQUIRED';
  end if;
  if nullif(btrim(requested_name), '') is null
    or requested_student_year not between 0 and 99
    or requested_joined_year not between 1977 and 2100
    or requested_position not in ('PG', 'SG', 'SF', 'PF', 'C', '미정')
    or requested_jersey_number not between 0 and 99
    or requested_membership_status not in ('yb', 'ob', 'military_leave', 'graduated', 'inactive')
    or requested_leadership_role not in ('member', 'manager', 'captain', 'admin')
    or cardinality(requested_team_codes) < 1
    or not requested_team_codes <@ array['ENCBA', 'BEN']::text[] then
    raise exception 'ENCBA_INVALID_MEMBER_PROFILE';
  end if;

  if requested_directory_id like 'allowlist:%' then
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
        leadership_role = requested_leadership_role,
        is_admin = requested_leadership_role = 'admin',
        is_schedule_manager = requested_leadership_role in ('admin', 'captain'),
        is_active = requested_active
    where id = substring(requested_directory_id from 11)::bigint;
    return;
  end if;

  target_profile := requested_directory_id::uuid;
  update public.profiles
  set name = btrim(requested_name),
      display_name = btrim(requested_name),
      student_year = requested_student_year,
      joined_year = requested_joined_year,
      phone = coalesce(requested_phone, ''),
      position = requested_position,
      jersey_number = requested_jersey_number,
      membership_status = requested_membership_status::public.membership_status,
      leadership_role = requested_leadership_role,
      is_admin = requested_leadership_role = 'admin',
      is_schedule_manager = requested_leadership_role in ('admin', 'captain'),
      is_active = requested_active,
      badge = case requested_membership_status
        when 'military_leave' then '군복무'
        when 'graduated' then '졸업'
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
      leadership_role = requested_leadership_role,
      is_admin = requested_leadership_role = 'admin',
      is_schedule_manager = requested_leadership_role in ('admin', 'captain'),
      is_active = requested_active
  where consumed_by = target_profile;
end;
$$;

revoke all on function public.admin_update_member(
  text, text, smallint, smallint, text, text, smallint, text, text[], text, boolean
) from public;
grant execute on function public.admin_update_member(
  text, text, smallint, smallint, text, text, smallint, text, text[], text, boolean
) to authenticated;

commit;
