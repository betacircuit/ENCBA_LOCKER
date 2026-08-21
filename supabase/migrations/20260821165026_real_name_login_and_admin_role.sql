begin;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

create or replace function private.resolve_login_email(requested_identifier text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized text := lower(btrim(coalesce(requested_identifier, '')));
  resolved_email text;
begin
  if normalized = '' or char_length(normalized) > 254 or normalized ~ '\s' then
    return null;
  end if;

  if position('@' in normalized) > 0 then
    if normalized !~ '^[^@]+@([a-z0-9-]+\.)*snu\.ac\.kr$' then
      return normalized;
    end if;
    select lower(account.email)
      into resolved_email
    from public.profiles as profile
    join auth.users as account on account.id = profile.id
    where profile.is_active
      and lower(profile.email) = normalized
    limit 1;
  elsif normalized ~ '^[a-z0-9._-]{1,64}$' then
    select case when count(*) = 1 then min(lower(account.email)) end
      into resolved_email
    from public.profiles as profile
    join auth.users as account on account.id = profile.id
    where profile.is_active
      and lower(split_part(profile.email, '@', 1)) = normalized
      and lower(profile.email) ~ '^[^@]+@([a-z0-9-]+\.)*snu\.ac\.kr$'
    ;
  end if;

  return resolved_email;
end;
$$;

revoke all on function private.resolve_login_email(text) from public;
grant execute on function private.resolve_login_email(text) to anon, authenticated;

create or replace function public.resolve_login_email(requested_identifier text)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select private.resolve_login_email(requested_identifier);
$$;

revoke all on function public.resolve_login_email(text) from public;
grant execute on function public.resolve_login_email(text) to anon, authenticated;

-- 타인에게 보이는 이름은 가입 명단에서 검증한 name과 항상 같게 유지한다.
update public.profiles
set display_name = name
where display_name is distinct from name;

create or replace function public.protect_profile_authorization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then return new; end if;
  if not public.is_encba_admin() then
    if new.is_admin is distinct from old.is_admin
      or new.is_active is distinct from old.is_active
      or new.membership_status is distinct from old.membership_status
      or new.generation is distinct from old.generation
      or new.badge is distinct from old.badge
      or new.is_schedule_manager is distinct from old.is_schedule_manager
      or new.leadership_role is distinct from old.leadership_role
      or new.name is distinct from old.name
      or new.display_name is distinct from old.display_name
      or new.email is distinct from old.email then
      raise exception 'ENCBA_PROFILE_AUTHORIZATION_FIELDS_ARE_ADMIN_ONLY';
    end if;
  end if;
  new.display_name := new.name;
  return new;
end;
$$;

revoke update (display_name) on public.profiles from authenticated;

-- 이민섭 부원은 표시 직책과 실제 관리자 권한을 같은 값으로 맞춘다.
update public.member_allowlist
set leadership_role = 'admin',
    is_admin = true,
    is_schedule_manager = true
where login_name = '이민섭';

update public.profiles as profile
set leadership_role = 'admin',
    is_admin = true,
    is_schedule_manager = true,
    display_name = profile.name
from public.member_allowlist as allowed
where allowed.login_name = '이민섭'
  and allowed.consumed_by = profile.id;

commit;
