begin;

-- Google 사용자는 OAuth 인증 뒤 회원정보를 입력하므로 auth.users 생성 시에는
-- 학교 이메일만 검증하고, 프로필과 가입 명단 소비는 완료 RPC에서 처리한다.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  allowlist_enabled boolean;
  allowed_member public.member_allowlist%rowtype;
  is_google boolean;
begin
  is_google := coalesce(new.raw_app_meta_data ->> 'provider', '') = 'google'
    or coalesce(new.raw_app_meta_data -> 'providers', '[]'::jsonb) ? 'google';

  if is_google then
    if new.email is null or not (
      lower(new.email) ~ '^[^@]+@([a-z0-9-]+\.)*snu\.ac\.kr$'
    ) then
      raise exception 'ENCBA_SNU_GOOGLE_ACCOUNT_REQUIRED' using errcode = '42501';
    end if;
    return new;
  end if;

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

drop function if exists public.complete_google_registration(
  text, smallint, smallint, text, text, smallint
);

create function public.complete_google_registration(
  requested_name text,
  requested_student_year smallint,
  requested_joined_year smallint,
  requested_phone text,
  requested_position text,
  requested_jersey_number smallint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  providers jsonb := coalesce(
    auth.jwt() -> 'app_metadata' -> 'providers',
    '[]'::jsonb
  );
  primary_provider text := coalesce(
    auth.jwt() -> 'app_metadata' ->> 'provider',
    ''
  );
  allowed_member public.member_allowlist%rowtype;
begin
  if current_user_id is null
    or not (primary_provider = 'google' or providers ? 'google') then
    raise exception 'ENCBA_GOOGLE_AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not (current_email ~ '^[^@]+@([a-z0-9-]+\.)*snu\.ac\.kr$') then
    raise exception 'ENCBA_SNU_GOOGLE_ACCOUNT_REQUIRED' using errcode = '42501';
  end if;
  if nullif(btrim(requested_name), '') is null
    or char_length(btrim(requested_name)) > 40
    or requested_student_year not between 0 and 99
    or requested_joined_year not between 1977 and extract(year from current_date)::smallint
    or nullif(btrim(coalesce(requested_phone, '')), '') is null
    or char_length(coalesce(requested_phone, '')) > 30
    or requested_position not in ('PG', 'SG', 'SF', 'PF', 'C', '미정')
    or requested_jersey_number not between 0 and 99 then
    raise exception 'ENCBA_GOOGLE_REGISTRATION_INVALID';
  end if;

  -- 네트워크 재시도 시 이미 생성된 프로필을 중복 생성하지 않는다.
  if exists (
    select 1 from public.profiles profile where profile.id = current_user_id
  ) then
    return;
  end if;

  select * into allowed_member
  from public.member_allowlist allowed
  where allowed.login_name = btrim(requested_name)
    and allowed.is_active
  for update;

  if not found
    or (allowed_member.consumed_by is not null
      and allowed_member.consumed_by is distinct from current_user_id) then
    raise exception 'ENCBA_MEMBER_NOT_ALLOWLISTED_OR_INACTIVE' using errcode = '42501';
  end if;

  update public.member_allowlist
  set consumed_by = current_user_id, consumed_at = now()
  where id = allowed_member.id;

  insert into public.profiles (
    id, email, name, display_name, student_year, generation, joined_year,
    phone, position, jersey_number, membership_status, badge,
    is_admin, is_schedule_manager, is_active, leadership_role,
    is_reservation_manager, department, is_freshman
  ) values (
    current_user_id,
    current_email,
    allowed_member.name,
    allowed_member.name,
    coalesce(allowed_member.student_year, requested_student_year),
    coalesce(allowed_member.generation, 1),
    coalesce(allowed_member.joined_year, requested_joined_year),
    btrim(coalesce(requested_phone, '')),
    requested_position,
    requested_jersey_number,
    allowed_member.membership_status,
    case allowed_member.membership_status
      when 'military_leave' then '군복무'
      when 'graduated' then '졸업'
      else null
    end,
    allowed_member.is_admin,
    allowed_member.is_schedule_manager,
    true,
    allowed_member.leadership_role,
    allowed_member.is_reservation_manager,
    allowed_member.department,
    allowed_member.is_freshman
  );

  insert into public.profile_teams (profile_id, team_id)
  select current_user_id, team.id
  from public.teams team
  where team.code = any(allowed_member.team_codes);
end;
$$;

revoke all on function public.complete_google_registration(
  text, smallint, smallint, text, text, smallint
) from public, anon;
grant execute on function public.complete_google_registration(
  text, smallint, smallint, text, text, smallint
) to authenticated;

commit;
