begin;

alter table public.member_allowlist
  add column if not exists is_freshman boolean not null default false;
alter table public.profiles
  add column if not exists is_freshman boolean not null default false;

update public.member_allowlist
set is_freshman = true
where joined_year = extract(year from current_date)::smallint;

update public.profiles
set is_freshman = true
where joined_year = extract(year from current_date)::smallint;

create index if not exists member_allowlist_freshman_active_idx
  on public.member_allowlist (is_freshman, is_active)
  where is_freshman;
create index if not exists profiles_freshman_active_idx
  on public.profiles (is_freshman, is_active)
  where is_freshman;

create or replace function public.sync_reservation_role_on_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles as profile
  set is_reservation_manager = allowed.is_reservation_manager,
      department = allowed.department,
      is_freshman = allowed.is_freshman
  from public.member_allowlist as allowed
  where profile.id = new.id
    and allowed.consumed_by = new.id;
  return new;
end;
$$;

create or replace function public.set_member_freshman(
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
  if not public.is_encba_admin() then
    raise exception '관리자만 신입생 여부를 변경할 수 있습니다.' using errcode = '42501';
  end if;

  if requested_directory_id like 'allowlist:%' then
    allowlist_id := substring(requested_directory_id from 11)::bigint;
    update public.member_allowlist
    set is_freshman = requested_value
    where id = allowlist_id;
    update public.profiles as profile
    set is_freshman = requested_value
    from public.member_allowlist as allowed
    where allowed.id = allowlist_id and profile.id = allowed.consumed_by;
  else
    profile_id := requested_directory_id::uuid;
    update public.profiles set is_freshman = requested_value where id = profile_id;
    update public.member_allowlist
    set is_freshman = requested_value
    where consumed_by = profile_id;
  end if;
end;
$$;

revoke all on function public.set_member_freshman(text, boolean) from public, anon;
grant execute on function public.set_member_freshman(text, boolean) to authenticated;

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
  leadership_role text,
  is_reservation_manager boolean,
  department text,
  is_freshman boolean
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
    coalesce(profile.leadership_role, allowed.leadership_role, 'member'),
    coalesce(profile.is_reservation_manager, allowed.is_reservation_manager, false),
    coalesce(nullif(profile.department, ''), allowed.department, ''),
    coalesce(profile.is_freshman, allowed.is_freshman, false)
  from public.member_allowlist as allowed
  left join public.profiles as profile on profile.id = allowed.consumed_by
  where (select auth.uid()) is not null
    and (
      requested_status = 'all'
      or (requested_status = 'military'
          and coalesce(profile.membership_status, allowed.membership_status) = 'military_leave')
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

create table if not exists public.announcement_event_links (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (announcement_id, event_id)
);

create index if not exists announcement_event_links_event_idx
  on public.announcement_event_links (event_id, announcement_id);

alter table public.announcement_event_links enable row level security;
drop policy if exists announcement_event_links_read on public.announcement_event_links;
create policy announcement_event_links_read on public.announcement_event_links
for select to authenticated
using ((select public.can_access_event(event_id)));
drop policy if exists announcement_event_links_manage on public.announcement_event_links;
create policy announcement_event_links_manage on public.announcement_event_links
for all to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));

revoke all on table public.announcement_event_links from public, anon;
grant select, insert, update, delete on table public.announcement_event_links to authenticated;

create or replace function public.replace_announcement_events(
  requested_announcement_id uuid,
  requested_event_ids uuid[]
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not public.is_encba_admin() then
    raise exception '관리자만 공지 일정을 연결할 수 있습니다.' using errcode = '42501';
  end if;
  if coalesce(cardinality(requested_event_ids), 0) > 30 then
    raise exception '공지에는 일정을 최대 30개까지 연결할 수 있습니다.' using errcode = '22023';
  end if;
  delete from public.announcement_event_links
  where announcement_id = requested_announcement_id;
  insert into public.announcement_event_links (announcement_id, event_id)
  select requested_announcement_id, event_id
  from unnest(coalesce(requested_event_ids, '{}'::uuid[])) as linked(event_id)
  on conflict do nothing;
end;
$$;

revoke all on function public.replace_announcement_events(uuid, uuid[]) from public, anon;
grant execute on function public.replace_announcement_events(uuid, uuid[]) to authenticated;

create or replace function public.get_attendance_report(
  requested_from timestamptz,
  requested_to timestamptz,
  requested_freshmen_only boolean default false
)
returns table (
  directory_id text,
  member_name text,
  student_year smallint,
  is_freshman boolean,
  event_id uuid,
  event_title text,
  event_start timestamptz,
  event_kind text,
  choice text,
  absence_reason text
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
    coalesce(profile.is_freshman, allowed.is_freshman, false),
    event.id,
    event.title,
    event.starts_at,
    event.kind,
    attendance.choice,
    attendance.absence_reason
  from public.member_allowlist as allowed
  left join public.profiles as profile on profile.id = allowed.consumed_by
  cross join public.events as event
  left join public.event_attendance as attendance
    on attendance.event_id = event.id and attendance.profile_id = profile.id
  where public.is_encba_admin()
    and coalesce(profile.is_active, allowed.is_active)
    and (not requested_freshmen_only
         or coalesce(profile.is_freshman, allowed.is_freshman, false))
    and event.cancelled_at is null
    and event.starts_at >= requested_from
    and event.starts_at < requested_to
    and event.response_enabled
  order by coalesce(profile.student_year, allowed.student_year, 0),
           coalesce(profile.display_name, allowed.name),
           event.starts_at;
$$;

revoke all on function public.get_attendance_report(timestamptz, timestamptz, boolean)
  from public, anon;
grant execute on function public.get_attendance_report(timestamptz, timestamptz, boolean)
  to authenticated;

commit;
