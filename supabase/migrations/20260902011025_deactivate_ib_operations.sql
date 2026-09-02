begin;

-- 홈커밍처럼 IB 운영도 기록은 보존한 채 화면과 교환 기능만 잠글 수 있게 한다.
alter table public.operation_assignments
  add column if not exists is_active boolean not null default true;

-- 이전 학기까지 함께 저장돼 있으면 현재 앱이 사용하던 "가장 최근 학기"만
-- 활성 상태로 시작한다. 학기 정보가 전혀 없는 레거시 데이터는 그대로 둔다.
with latest_period as (
  select academic_year, term
  from public.operation_assignments
  where academic_year is not null and term is not null
  order by academic_year desc, term desc
  limit 1
)
update public.operation_assignments as assignment
set is_active = case
  when exists (select 1 from latest_period) then exists (
    select 1
    from latest_period as period
    where period.academic_year = assignment.academic_year
      and period.term = assignment.term
  )
  else true
end;

create index if not exists operation_assignments_active_starts_idx
  on public.operation_assignments (starts_at, id)
  where is_active;

create or replace function public.list_my_operation_assignments()
returns table (
  id uuid,
  title text,
  starts_at timestamptz,
  ends_at timestamptz,
  location text,
  memo text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with my_assignments as (
    select assignment.*
    from public.operation_assignments as assignment
    where assignment.is_active
      and (
        assignment.profile_id = (select auth.uid())
        or assignment.assignee_name = (
          select profile.name
          from public.profiles as profile
          where profile.id = (select auth.uid())
        )
      )
  ),
  latest_period as (
    select assignment.academic_year, assignment.term
    from my_assignments as assignment
    where assignment.academic_year is not null
      and assignment.term is not null
    order by assignment.academic_year desc, assignment.term desc
    limit 1
  )
  select
    assignment.id,
    assignment.title,
    assignment.starts_at,
    assignment.ends_at,
    assignment.location,
    assignment.memo
  from my_assignments as assignment
  where (
    exists (
      select 1
      from latest_period as period
      where period.academic_year = assignment.academic_year
        and period.term = assignment.term
    )
    or (
      not exists (select 1 from latest_period)
      and assignment.academic_year is null
    )
  )
  order by assignment.starts_at, assignment.id
  limit 300;
$$;

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
    and assignment.is_active
    and assignment.profile_id is not null
    and assignment.ends_at >= now()
  order by assignment.starts_at, assignment.id
  limit 300;
$$;

create or replace function public.import_ib_operation_assignments(
  requested_file_name text,
  requested_academic_year integer,
  requested_term integer,
  requested_assignments jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  imported_count integer := 0;
  unmatched_count integer := 0;
begin
  if caller_id is null or not (select public.is_encba_admin()) then
    raise exception '관리자 또는 주장만 IB 운영표를 가져올 수 있습니다.'
      using errcode = '42501';
  end if;

  if requested_term not in (1, 2)
    or requested_academic_year not between 2020 and 2100
    or jsonb_typeof(requested_assignments) <> 'array'
  then
    raise exception '운영표 학기 또는 행 형식이 올바르지 않습니다.'
      using errcode = '22023';
  end if;

  update public.operation_swap_requests as request
  set status = 'cancelled', responded_at = now()
  where request.status = 'pending'
    and exists (
      select 1
      from public.operation_assignments as assignment
      where assignment.is_active
        and assignment.id in (
          request.requester_assignment_id,
          request.target_assignment_id
        )
    );

  update public.operation_assignments
  set is_active = false
  where is_active;

  delete from public.operation_assignments
  where academic_year = requested_academic_year
    and term = requested_term
    and source_file_name is not null;

  with source_rows as (
    select
      nullif(btrim(item ->> 'assignee_name'), '') as assignee_name,
      nullif(btrim(item ->> 'title'), '') as title,
      (item ->> 'starts_at')::timestamptz as starts_at,
      (item ->> 'ends_at')::timestamptz as ends_at,
      nullif(btrim(item ->> 'location'), '') as location,
      nullif(btrim(item ->> 'memo'), '') as memo,
      nullif(btrim(item ->> 'source_sheet'), '') as source_sheet,
      (item ->> 'source_row')::integer as source_row,
      (item ->> 'source_column')::integer as source_column
    from jsonb_array_elements(requested_assignments) as item
  ),
  inserted as (
    insert into public.operation_assignments (
      profile_id,
      assignee_name,
      title,
      starts_at,
      ends_at,
      location,
      memo,
      created_by,
      academic_year,
      term,
      source_file_name,
      source_sheet,
      source_row,
      source_column,
      is_active
    )
    select
      (
        select profile.id
        from public.profiles as profile
        where profile.name = source.assignee_name
        order by profile.is_active desc, profile.created_at
        limit 1
      ),
      source.assignee_name,
      source.title,
      source.starts_at,
      source.ends_at,
      source.location,
      source.memo,
      caller_id,
      requested_academic_year,
      requested_term,
      requested_file_name,
      source.source_sheet,
      source.source_row,
      source.source_column,
      true
    from source_rows as source
    where source.assignee_name is not null
      and source.title is not null
      and source.ends_at > source.starts_at
    returning profile_id
  )
  select
    count(*)::integer,
    count(*) filter (where profile_id is null)::integer
  into imported_count, unmatched_count
  from inserted;

  return jsonb_build_object(
    'imported', imported_count,
    'unmatched', unmatched_count
  );
end;
$$;

create or replace function public.deactivate_ib_operations()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  deactivated_count integer := 0;
begin
  if caller_id is null or not (select public.is_encba_admin()) then
    raise exception '관리자 또는 주장만 IB 운영을 비활성화할 수 있습니다.'
      using errcode = '42501';
  end if;

  update public.operation_swap_requests as request
  set status = 'cancelled', responded_at = now()
  where request.status = 'pending'
    and exists (
      select 1
      from public.operation_assignments as assignment
      where assignment.is_active
        and assignment.id in (
          request.requester_assignment_id,
          request.target_assignment_id
        )
    );

  update public.operation_assignments
  set is_active = false
  where is_active;
  get diagnostics deactivated_count = row_count;

  return deactivated_count > 0;
end;
$$;

-- 오래 열린 클라이언트가 비활성 배정 ID로 교환 RPC를 직접 호출해도 막는다.
create or replace function public.guard_active_operation_swap()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (
    select count(*)
    from public.operation_assignments as assignment
    where assignment.is_active
      and assignment.id in (
        new.requester_assignment_id,
        new.target_assignment_id
      )
  ) <> 2 then
    raise exception '비활성화된 IB 운영 일정은 교환할 수 없습니다.'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists operation_swaps_require_active_assignments
  on public.operation_swap_requests;
create trigger operation_swaps_require_active_assignments
before insert or update on public.operation_swap_requests
for each row execute function public.guard_active_operation_swap();

revoke all on function public.list_my_operation_assignments()
  from public, anon;
grant execute on function public.list_my_operation_assignments()
  to authenticated;
revoke all on function public.list_operation_exchange_board()
  from public, anon;
grant execute on function public.list_operation_exchange_board()
  to authenticated;
revoke all on function public.import_ib_operation_assignments(text, integer, integer, jsonb)
  from public, anon;
grant execute on function public.import_ib_operation_assignments(text, integer, integer, jsonb)
  to authenticated;
revoke all on function public.deactivate_ib_operations()
  from public, anon;
grant execute on function public.deactivate_ib_operations()
  to authenticated;
revoke all on function public.guard_active_operation_swap()
  from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;
