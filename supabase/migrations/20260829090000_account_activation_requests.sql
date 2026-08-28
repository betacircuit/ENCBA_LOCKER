-- 계정 활성화 요청함
--
-- 비활성 계정으로 로그인하면 앱이 곧바로 로그아웃시키기 때문에, 그 자리에서
-- 관리자에게 활성화를 부탁할 방법이 없었다. 로그인 화면에서 누구든(세션 없이)
-- 부를 수 있는 요청 함수를 두고, 관리자에게는 실시간 알림과 처리 목록을 준다.

begin;

create table if not exists public.account_activation_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  requester_name text not null default '',
  requester_email text not null default '',
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'declined')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete set null
);

-- 한 사람이 여러 번 눌러도 대기 중인 요청은 하나만 남는다.
create unique index if not exists account_activation_requests_pending_idx
  on public.account_activation_requests (profile_id)
  where status = 'pending';

create index if not exists account_activation_requests_created_at_idx
  on public.account_activation_requests (created_at desc);

alter table public.account_activation_requests enable row level security;

-- 요청은 security definer 함수로만 만들어진다. 직접 insert 하는 정책은 두지 않는다.
drop policy if exists account_activation_requests_read_admin
  on public.account_activation_requests;
create policy account_activation_requests_read_admin
  on public.account_activation_requests
  for select to authenticated using (public.is_encba_admin());

drop policy if exists account_activation_requests_update_admin
  on public.account_activation_requests;
create policy account_activation_requests_update_admin
  on public.account_activation_requests
  for update to authenticated
  using (public.is_encba_admin())
  with check (public.is_encba_admin());

-- 관리자 화면이 재접속 없이 새 요청을 받도록 실시간 발행에 올린다.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'account_activation_requests'
  ) then
    alter publication supabase_realtime
      add table public.account_activation_requests;
  end if;
end
$$;

-- 로그인 화면에서 부른다. 세션이 없어도 되게 anon에도 실행 권한을 준다.
-- 계정이 있는지 없는지 알려 주지 않으려고, 어떤 경우에도 같은 값을 돌려준다.
create or replace function public.request_account_activation(
  requested_email text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.profiles%rowtype;
begin
  if requested_email is null or length(trim(requested_email)) = 0 then
    return true;
  end if;

  select * into target
  from public.profiles
  where lower(email) = lower(trim(requested_email))
  limit 1;

  if not found or target.is_active then
    return true;
  end if;

  insert into public.account_activation_requests (
    profile_id, requester_name, requester_email
  )
  values (
    target.id,
    coalesce(nullif(target.display_name, ''), target.name, ''),
    target.email
  )
  on conflict (profile_id) where status = 'pending' do nothing;

  return true;
end;
$$;

revoke all on function public.request_account_activation(text) from public;
grant execute on function public.request_account_activation(text) to anon;
grant execute on function public.request_account_activation(text) to authenticated;

-- 관리자가 요청을 처리한다. 승인하면 계정과 명단을 함께 활성화한다.
create or replace function public.resolve_account_activation(
  requested_request_id uuid,
  requested_approve boolean
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
    raise exception 'ENCBA_ADMIN_REQUIRED';
  end if;

  select profile_id into target_profile
  from public.account_activation_requests
  where id = requested_request_id and status = 'pending';

  if not found then
    return;
  end if;

  if requested_approve then
    update public.profiles set is_active = true where id = target_profile;
    update public.member_allowlist
    set is_active = true
    where consumed_by = target_profile;
  end if;

  update public.account_activation_requests
  set status = case when requested_approve then 'approved' else 'declined' end,
      resolved_at = now(),
      resolved_by = (select auth.uid())
  where id = requested_request_id;
end;
$$;

revoke all on function public.resolve_account_activation(uuid, boolean) from public;
grant execute on function public.resolve_account_activation(uuid, boolean)
  to authenticated;

create or replace function public.list_account_activation_requests()
returns table (
  id uuid,
  profile_id uuid,
  requester_name text,
  requester_email text,
  status text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.profile_id, r.requester_name, r.requester_email,
         r.status, r.created_at
  from public.account_activation_requests r
  where public.is_encba_admin() and r.status = 'pending'
  order by r.created_at desc
  limit 100;
$$;

revoke all on function public.list_account_activation_requests() from public;
grant execute on function public.list_account_activation_requests()
  to authenticated;

notify pgrst, 'reload schema';

commit;
