begin;

-- 부원의 불참 사유는 해당 일정을 볼 수 있는 모든 팀원에게 공개한다.
drop policy if exists attendance_read on public.event_attendance;
create policy attendance_read
on public.event_attendance
for select
to authenticated
using ((select public.can_access_event(event_id)));

create index if not exists event_attendance_event_choice_idx
  on public.event_attendance (event_id, choice, responded_at desc);

-- 앞선 호환 마이그레이션이 축약했던 멤버 디렉터리 반환값을 복구한다.
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
  leadership_role text
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
    coalesce(profile.leadership_role, allowed.leadership_role, 'member')
  from public.member_allowlist as allowed
  left join public.profiles as profile on profile.id = allowed.consumed_by
  where (select auth.uid()) is not null
    and (
      requested_status = 'all'
      or (
        requested_status = 'military'
        and coalesce(profile.membership_status, allowed.membership_status) = 'military_leave'
      )
    )
    and (
      nullif(btrim(requested_query), '') is null
      or coalesce(profile.display_name, allowed.name) ilike '%' || btrim(requested_query) || '%'
      or lpad(coalesce(profile.student_year, allowed.student_year, 0)::text, 2, '0')
        = regexp_replace(requested_query, '[^0-9]', '', 'g')
    )
  order by coalesce(profile.student_year, allowed.student_year, 0),
           coalesce(profile.display_name, allowed.name);
$$;

revoke all on function public.list_member_directory(text, text) from public, anon;
grant execute on function public.list_member_directory(text, text) to authenticated;

create table public.operation_swap_requests (
  id uuid primary key default gen_random_uuid(),
  requester_assignment_id uuid not null
    references public.operation_assignments(id) on delete cascade,
  target_assignment_id uuid not null
    references public.operation_assignments(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  message text not null default '' check (char_length(message) <= 300),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_assignment_id <> target_assignment_id),
  check (requester_id <> target_id)
);

create unique index operation_swap_pending_pair_idx
  on public.operation_swap_requests (requester_assignment_id, target_assignment_id)
  where status = 'pending';
create index operation_swap_target_status_idx
  on public.operation_swap_requests (target_id, status, created_at desc);
create index operation_swap_requester_status_idx
  on public.operation_swap_requests (requester_id, status, created_at desc);

alter table public.operation_swap_requests enable row level security;

create policy operation_swaps_read_participants
on public.operation_swap_requests
for select
to authenticated
using (
  requester_id = (select auth.uid())
  or target_id = (select auth.uid())
  or (select public.is_encba_admin())
);

create or replace function public.list_operation_exchange_board()
returns table (
  id uuid,
  assignee_id uuid,
  assignee_name text,
  title text,
  starts_at timestamptz,
  ends_at timestamptz,
  location text,
  memo text,
  is_mine boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    assignment.id,
    assignment.profile_id,
    coalesce(profile.display_name, profile.name, assignment.assignee_name),
    assignment.title,
    assignment.starts_at,
    assignment.ends_at,
    assignment.location,
    assignment.memo,
    assignment.profile_id = (select auth.uid())
  from public.operation_assignments as assignment
  left join public.profiles as profile on profile.id = assignment.profile_id
  where (select auth.uid()) is not null
    and assignment.profile_id is not null
    and assignment.ends_at >= now()
  order by assignment.starts_at, assignment.id
  limit 300;
$$;

create or replace function public.list_my_operation_swap_requests()
returns table (
  id uuid,
  requester_assignment_id uuid,
  target_assignment_id uuid,
  direction text,
  counterpart_name text,
  requester_title text,
  requester_starts_at timestamptz,
  target_title text,
  target_starts_at timestamptz,
  status text,
  message text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    request.id,
    request.requester_assignment_id,
    request.target_assignment_id,
    case when request.target_id = (select auth.uid()) then 'incoming' else 'outgoing' end,
    case
      when request.target_id = (select auth.uid())
        then coalesce(requester.display_name, requester.name)
      else coalesce(target.display_name, target.name)
    end,
    requester_assignment.title,
    requester_assignment.starts_at,
    target_assignment.title,
    target_assignment.starts_at,
    request.status,
    request.message,
    request.created_at
  from public.operation_swap_requests as request
  join public.operation_assignments as requester_assignment
    on requester_assignment.id = request.requester_assignment_id
  join public.operation_assignments as target_assignment
    on target_assignment.id = request.target_assignment_id
  join public.profiles as requester on requester.id = request.requester_id
  join public.profiles as target on target.id = request.target_id
  where request.requester_id = (select auth.uid())
     or request.target_id = (select auth.uid())
  order by request.created_at desc
  limit 100;
$$;

create or replace function public.create_operation_swap_request(
  requested_own_assignment uuid,
  requested_target_assignment uuid,
  requested_message text default ''
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  own_assignment public.operation_assignments%rowtype;
  target_assignment public.operation_assignments%rowtype;
  request_id uuid;
begin
  if caller_id is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  if char_length(coalesce(requested_message, '')) > 300 then
    raise exception '교환 메시지는 300자까지 입력할 수 있습니다.' using errcode = '22023';
  end if;

  select * into own_assignment
  from public.operation_assignments
  where id = requested_own_assignment
  for update;
  select * into target_assignment
  from public.operation_assignments
  where id = requested_target_assignment
  for update;

  if own_assignment.id is null or own_assignment.profile_id <> caller_id then
    raise exception '내 운영 일정만 교환 요청할 수 있습니다.' using errcode = '42501';
  end if;
  if target_assignment.id is null
    or target_assignment.profile_id is null
    or target_assignment.profile_id = caller_id
  then
    raise exception '교환할 상대 운영 일정이 올바르지 않습니다.' using errcode = '22023';
  end if;
  if own_assignment.ends_at < now() or target_assignment.ends_at < now() then
    raise exception '지난 운영 일정은 교환할 수 없습니다.' using errcode = '22023';
  end if;

  insert into public.operation_swap_requests (
    requester_assignment_id,
    target_assignment_id,
    requester_id,
    target_id,
    message
  ) values (
    own_assignment.id,
    target_assignment.id,
    caller_id,
    target_assignment.profile_id,
    btrim(coalesce(requested_message, ''))
  )
  returning id into request_id;
  return request_id;
end;
$$;

create or replace function public.respond_operation_swap_request(
  requested_swap_id uuid,
  requested_accept boolean
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  swap_request public.operation_swap_requests%rowtype;
  requester_assignment public.operation_assignments%rowtype;
  target_assignment public.operation_assignments%rowtype;
  requester_name text;
  target_name text;
begin
  select * into swap_request
  from public.operation_swap_requests
  where id = requested_swap_id
  for update;

  if swap_request.id is null or swap_request.target_id <> caller_id then
    raise exception '이 교환 요청에 응답할 권한이 없습니다.' using errcode = '42501';
  end if;
  if swap_request.status <> 'pending' then
    raise exception '이미 처리된 교환 요청입니다.' using errcode = '22023';
  end if;

  if not requested_accept then
    update public.operation_swap_requests
    set status = 'rejected', responded_at = now()
    where id = swap_request.id;
    return 'rejected';
  end if;

  select * into requester_assignment
  from public.operation_assignments
  where id = swap_request.requester_assignment_id
  for update;
  select * into target_assignment
  from public.operation_assignments
  where id = swap_request.target_assignment_id
  for update;

  if requester_assignment.profile_id <> swap_request.requester_id
    or target_assignment.profile_id <> swap_request.target_id
    or requester_assignment.ends_at < now()
    or target_assignment.ends_at < now()
  then
    update public.operation_swap_requests
    set status = 'cancelled', responded_at = now()
    where id = swap_request.id;
    raise exception '배정이 변경되었거나 지난 일정이라 교환할 수 없습니다.' using errcode = '40001';
  end if;

  select coalesce(display_name, name) into requester_name
  from public.profiles where id = swap_request.requester_id;
  select coalesce(display_name, name) into target_name
  from public.profiles where id = swap_request.target_id;

  update public.operation_assignments
  set profile_id = case
        when id = requester_assignment.id then swap_request.target_id
        else swap_request.requester_id
      end,
      assignee_name = case
        when id = requester_assignment.id then target_name
        else requester_name
      end
  where id in (requester_assignment.id, target_assignment.id);

  update public.operation_swap_requests
  set status = 'accepted', responded_at = now()
  where id = swap_request.id;
  return 'accepted';
end;
$$;

revoke all on function public.list_operation_exchange_board() from public, anon;
revoke all on function public.list_my_operation_swap_requests() from public, anon;
revoke all on function public.create_operation_swap_request(uuid, uuid, text) from public, anon;
revoke all on function public.respond_operation_swap_request(uuid, boolean) from public, anon;
grant execute on function public.list_operation_exchange_board() to authenticated;
grant execute on function public.list_my_operation_swap_requests() to authenticated;
grant execute on function public.create_operation_swap_request(uuid, uuid, text) to authenticated;
grant execute on function public.respond_operation_swap_request(uuid, boolean) to authenticated;

grant select on public.operation_swap_requests to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'operation_swap_requests'
  ) then
    alter publication supabase_realtime add table public.operation_swap_requests;
  end if;
end;
$$;

notify pgrst, 'reload schema';

commit;
