begin;

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

revoke all on function public.list_my_operation_assignments()
  from public, anon;
grant execute on function public.list_my_operation_assignments()
  to authenticated;

commit;
