begin;

-- IB 운영표는 학기 단위로 교체된다. 사용자가 배정된 가장 최근 학기의
-- 일정은 경기 날짜가 지났더라도 모두 보여 준다.
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
    where assignment.profile_id = (select auth.uid())
       or assignment.assignee_name = (
         select profile.name
         from public.profiles as profile
         where profile.id = (select auth.uid())
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

revoke all on function public.list_my_operation_assignments()
  from public, anon;
grant execute on function public.list_my_operation_assignments()
  to authenticated;

commit;
