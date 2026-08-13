begin;

create or replace function public.is_primary_encba_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select profile.is_admin and profile.leadership_role = 'admin'
      from public.profiles as profile
      where profile.id = (select auth.uid())
    ),
    false
  );
$$;

revoke all on function public.is_primary_encba_admin() from public, anon;
grant execute on function public.is_primary_encba_admin() to authenticated;

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
  if not public.is_primary_encba_admin() then
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
    where allowed.id = allowlist_id and profile.id = allowed.consumed_by;
  else
    profile_id := requested_directory_id::uuid;
    update public.profiles set is_reservation_manager = requested_value where id = profile_id;
    update public.member_allowlist set is_reservation_manager = requested_value where consumed_by = profile_id;
  end if;
end;
$$;

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
  if not public.is_primary_encba_admin() then
    raise exception '관리자만 학과 정보를 변경할 수 있습니다.' using errcode = '42501';
  end if;
  if char_length(coalesce(requested_department, '')) > 100 then
    raise exception '학과 정보가 너무 깁니다.' using errcode = '22023';
  end if;
  if requested_directory_id like 'allowlist:%' then
    allowlist_id := substring(requested_directory_id from 11)::bigint;
    update public.member_allowlist set department = btrim(coalesce(requested_department, '')) where id = allowlist_id;
    update public.profiles as profile
    set department = btrim(coalesce(requested_department, ''))
    from public.member_allowlist as allowed
    where allowed.id = allowlist_id and profile.id = allowed.consumed_by;
  else
    profile_id := requested_directory_id::uuid;
    update public.profiles set department = btrim(coalesce(requested_department, '')) where id = profile_id;
    update public.member_allowlist set department = btrim(coalesce(requested_department, '')) where consumed_by = profile_id;
  end if;
end;
$$;

create or replace function public.admin_sync_member_contacts(requested_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_count integer;
begin
  if not public.is_primary_encba_admin() then
    raise exception '관리자만 명단 연락처를 동기화할 수 있습니다.' using errcode = '42501';
  end if;
  if jsonb_typeof(requested_rows) <> 'array' or jsonb_array_length(requested_rows) > 200 then
    raise exception '명단 형식이 올바르지 않습니다.' using errcode = '22023';
  end if;
  with source as (
    select btrim(item ->> 'name') as name,
           regexp_replace(coalesce(item ->> 'phone', ''), '[^0-9]', '', 'g') as phone
    from jsonb_array_elements(requested_rows) as item
    where nullif(btrim(item ->> 'name'), '') is not null
  ), updated as (
    update public.member_allowlist as allowed
    set phone = source.phone
    from source
    where allowed.name = source.name and source.phone ~ '^01[016789][0-9]{7,8}$'
    returning allowed.id
  )
  select count(*) into changed_count from updated;
  update public.profiles as profile
  set phone = allowed.phone
  from public.member_allowlist as allowed
  where profile.id = allowed.consumed_by and allowed.phone ~ '^01[016789][0-9]{7,8}$';
  return changed_count;
end;
$$;

commit;
