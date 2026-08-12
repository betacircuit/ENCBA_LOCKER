begin;

-- 자개는 훈련 계열 일정이라 유니폼 선택이 필요하지 않다.
alter table public.events
  drop constraint if exists events_kind_check;

alter table public.events
  add constraint events_kind_check check (kind in (
    'training', 'morning', 'free_open', 'internal', 'pickup',
    'ib_division_1', 'ib_division_2', 'ib_freshman', 'scrimmage',
    'three_way', 'external', 'operation', 'homecoming'
  ));

do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select conname
    from pg_constraint
    where conrelid = 'public.events'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%cardinality(uniform_colors)%'
  loop
    execute format(
      'alter table public.events drop constraint %I',
      constraint_name
    );
  end loop;
end;
$$;

alter table public.events
  add constraint events_uniform_required_check check (
    kind in ('training', 'morning', 'free_open')
    or cardinality(uniform_colors) > 0
  );

-- 운영표는 가입 전 이름도 잃지 않고 보존하며, 가입 후 이름으로 자동 연결한다.
alter table public.operation_assignments
  alter column profile_id drop not null,
  add column if not exists assignee_name text,
  add column if not exists academic_year smallint,
  add column if not exists term smallint check (term in (1, 2)),
  add column if not exists source_file_name text,
  add column if not exists source_sheet text,
  add column if not exists source_row integer,
  add column if not exists source_column integer;

update public.operation_assignments as assignment
set assignee_name = profile.name
from public.profiles as profile
where assignment.profile_id = profile.id
  and assignment.assignee_name is null;

alter table public.operation_assignments
  add constraint operation_assignments_assignee_check check (
    profile_id is not null or nullif(btrim(assignee_name), '') is not null
  );

create index if not exists operation_assignments_name_starts_idx
  on public.operation_assignments (assignee_name, starts_at)
  where assignee_name is not null;

create index if not exists operation_assignments_period_idx
  on public.operation_assignments (academic_year, term, starts_at)
  where academic_year is not null;

create unique index if not exists operation_assignments_source_unique_idx
  on public.operation_assignments (
    academic_year,
    term,
    source_sheet,
    source_row,
    source_column,
    assignee_name
  )
  where source_file_name is not null;

drop policy if exists operations_read_own_or_admin
  on public.operation_assignments;
create policy operations_read_own_or_admin
on public.operation_assignments
for select
to authenticated
using (
  profile_id = (select auth.uid())
  or assignee_name = (
    select profile.name
    from public.profiles as profile
    where profile.id = (select auth.uid())
  )
  or (select public.is_encba_admin())
);

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
  select
    assignment.id,
    assignment.title,
    assignment.starts_at,
    assignment.ends_at,
    assignment.location,
    assignment.memo
  from public.operation_assignments as assignment
  where assignment.ends_at >= now() - interval '30 days'
    and (
      assignment.profile_id = (select auth.uid())
      or assignment.assignee_name = (
        select profile.name
        from public.profiles as profile
        where profile.id = (select auth.uid())
      )
    )
  order by assignment.starts_at, assignment.id
  limit 100;
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
  if caller_id is null or not exists (
    select 1
    from public.profiles as profile
    where profile.id = caller_id
      and profile.is_active
      and (profile.is_admin or profile.leadership_role = 'admin')
  ) then
    raise exception '관리자만 IB 운영표를 가져올 수 있습니다.'
      using errcode = '42501';
  end if;

  if requested_term not in (1, 2)
    or requested_academic_year not between 2020 and 2100
    or jsonb_typeof(requested_assignments) <> 'array'
  then
    raise exception '운영표 학기 또는 행 형식이 올바르지 않습니다.'
      using errcode = '22023';
  end if;

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
      source_column
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
      source.source_column
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

revoke all on function public.list_my_operation_assignments() from public;
grant execute on function public.list_my_operation_assignments() to authenticated;
revoke all on function public.import_ib_operation_assignments(text, integer, integer, jsonb)
  from public, anon;
grant execute on function public.import_ib_operation_assignments(text, integer, integer, jsonb)
  to authenticated;

commit;
