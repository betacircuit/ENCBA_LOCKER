begin;

drop function if exists public.complete_google_registration(
  text, smallint, smallint, text, text, smallint
);

-- Google 가입 분기를 추가하기 전의 명단 기반 사용자 생성 함수를 복원한다.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  allowlist_enabled boolean;
  allowed_member public.member_allowlist%rowtype;
begin
  select coalesce((value #>> '{}')::boolean, false)
    into allowlist_enabled
    from public.app_settings
    where key = 'enforce_member_allowlist';

  if allowlist_enabled and not exists (
    select 1 from public.member_allowlist a
    where a.login_name = btrim(new.raw_user_meta_data ->> 'name')
      and a.consumed_by is null
      and a.is_active
  ) then
    raise exception 'ENCBA_MEMBER_NOT_ALLOWLISTED_OR_INACTIVE';
  end if;

  select * into allowed_member
  from public.member_allowlist a
  where a.login_name = btrim(new.raw_user_meta_data ->> 'name')
    and a.consumed_by is null
    and a.is_active;

  insert into public.profiles (
    id, email, name, display_name, student_year, generation, joined_year,
    phone, position, jersey_number, membership_status, badge,
    is_admin, is_schedule_manager, is_active, leadership_role
  ) values (
    new.id,
    new.email,
    allowed_member.name,
    allowed_member.name,
    coalesce(allowed_member.student_year, (new.raw_user_meta_data ->> 'student_year')::smallint, 0),
    coalesce(allowed_member.generation, 1),
    coalesce(allowed_member.joined_year, (new.raw_user_meta_data ->> 'joined_year')::smallint),
    coalesce(nullif(allowed_member.phone, ''), new.raw_user_meta_data ->> 'phone', ''),
    coalesce(nullif(allowed_member.position, ''), new.raw_user_meta_data ->> 'position', '미정'),
    coalesce(nullif(allowed_member.jersey_number, 0), (new.raw_user_meta_data ->> 'jersey_number')::smallint, 0),
    allowed_member.membership_status,
    case allowed_member.membership_status
      when 'military_leave' then '군복무'
      when 'graduated' then '졸업'
      else null
    end,
    allowed_member.is_admin,
    allowed_member.is_schedule_manager,
    true,
    allowed_member.leadership_role
  );

  insert into public.profile_teams (profile_id, team_id)
  select new.id, t.id
  from public.teams t
  where t.code = any(coalesce(allowed_member.team_codes, array['ENCBA']::text[]));

  update public.member_allowlist
  set consumed_by = new.id, consumed_at = now()
  where id = allowed_member.id and consumed_by is null;
  return new;
end;
$$;

commit;
