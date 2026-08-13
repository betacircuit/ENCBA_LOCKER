begin;

create or replace function public.admin_sync_member_contacts(
  requested_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_count integer;
begin
  if not public.is_encba_admin() then
    raise exception '관리자만 명단 연락처를 동기화할 수 있습니다.' using errcode = '42501';
  end if;
  if jsonb_typeof(requested_rows) <> 'array' or jsonb_array_length(requested_rows) > 200 then
    raise exception '명단 형식이 올바르지 않습니다.' using errcode = '22023';
  end if;

  with source as (
    select
      btrim(item ->> 'name') as name,
      regexp_replace(coalesce(item ->> 'phone', ''), '[^0-9]', '', 'g') as phone
    from jsonb_array_elements(requested_rows) as item
    where nullif(btrim(item ->> 'name'), '') is not null
  ), updated as (
    update public.member_allowlist as allowed
    set phone = source.phone
    from source
    where allowed.name = source.name
      and source.phone ~ '^01[016789][0-9]{7,8}$'
    returning allowed.id, allowed.consumed_by, allowed.phone
  )
  select count(*) into changed_count from updated;

  update public.profiles as profile
  set phone = allowed.phone
  from public.member_allowlist as allowed
  where profile.id = allowed.consumed_by
    and allowed.phone ~ '^01[016789][0-9]{7,8}$';

  return changed_count;
end;
$$;

revoke all on function public.admin_sync_member_contacts(jsonb) from public, anon;
grant execute on function public.admin_sync_member_contacts(jsonb) to authenticated;

commit;
