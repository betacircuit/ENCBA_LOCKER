begin;

create extension if not exists citext with schema extensions;

create type public.membership_status as enum (
  'yb', 'ob', 'military_leave', 'graduated', 'inactive'
);
create type public.attendance_status as enum (
  'attending', 'late', 'absent', 'undecided'
);
create type public.video_category as enum ('highlight', 'review', 'shared');

create table public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

insert into public.app_settings (key, value)
values ('enforce_member_allowlist', 'true'::jsonb);

create table public.member_allowlist (
  email extensions.citext primary key,
  name text,
  student_year smallint check (student_year between 0 and 99),
  generation smallint check (generation > 0),
  team_codes text[] not null default array['ENCBA']::text[]
    check (team_codes <@ array['ENCBA', 'BEN']::text[] and cardinality(team_codes) > 0),
  consumed_by uuid references auth.users(id) on delete set null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email extensions.citext not null unique,
  name text not null check (char_length(name) between 1 and 40),
  student_year smallint not null check (student_year between 0 and 99),
  generation smallint not null check (generation between 1 and 200),
  phone text not null default '' check (char_length(phone) <= 30),
  position text not null default '미정'
    check (position in ('PG', 'SG', 'SF', 'PF', 'C', '미정')),
  jersey_number smallint not null default 0
    check (jersey_number between 0 and 99),
  membership_status public.membership_status not null default 'yb',
  badge text check (badge is null or char_length(badge) <= 20),
  avatar_path text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.teams (
  id bigint generated always as identity primary key,
  code text not null unique check (code ~ '^[A-Z0-9_-]{2,20}$'),
  name text not null,
  created_at timestamptz not null default now()
);

insert into public.teams (code, name)
values ('ENCBA', 'ENCBA'), ('BEN', 'BEN');

create table public.profile_teams (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  team_id bigint not null references public.teams(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, team_id)
);

create table public.seasons (
  id bigint generated always as identity primary key,
  name text not null unique,
  starts_on date not null,
  ends_on date not null,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create unique index seasons_one_active_idx
on public.seasons (is_active) where is_active;

create table public.leagues (
  id bigint generated always as identity primary key,
  season_id bigint not null references public.seasons(id) on delete cascade,
  code text not null,
  division smallint check (division in (1, 2)),
  name text not null,
  created_at timestamptz not null default now(),
  unique (season_id, code, division)
);

create table public.places (
  id bigint generated always as identity primary key,
  code text not null unique,
  name text not null,
  building text not null,
  naver_map_url text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.places (code, name, building, naver_map_url) values
  ('GYM_71', '71동 종합체육관', '71동', 'https://map.naver.com/p/entry/place/18733898'),
  ('NEW_GYM_71_1', '71-1동 신체육관', '71-1동', 'https://map.naver.com/p/entry/place/1985573410'),
  ('DORM_GYM_900', '900동 기숙사체육관', '900동', 'https://map.naver.com/p/entry/place/1289118439');

create table public.events (
  id uuid primary key default gen_random_uuid(),
  season_id bigint references public.seasons(id) on delete set null,
  league_id bigint references public.leagues(id) on delete set null,
  title text not null check (char_length(title) between 1 and 120),
  kind text not null check (kind in (
    'training', 'morning', 'internal', 'ib_division_1', 'ib_division_2',
    'scrimmage', 'three_way', 'external', 'operation', 'homecoming'
  )),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  place_id bigint references public.places(id) on delete restrict,
  place_label text,
  court text check (court is null or court in ('A코트', 'B코트', '전체')),
  target_team text not null default '전체'
    check (target_team in ('전체', 'ENCBA', 'BEN', 'ENCBA 1부', 'ENCBA 2부')),
  opponent text,
  uniform_color text check (uniform_color is null or uniform_color in ('검', '흰')),
  memo text not null check (char_length(memo) between 1 and 5000),
  capacity smallint check (capacity is null or capacity > 0),
  response_enabled boolean not null default true,
  response_deadline timestamptz not null,
  attending_count integer not null default 0 check (attending_count >= 0),
  recurrence_rule jsonb,
  parent_event_id uuid references public.events(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  check (ends_at > starts_at),
  check (response_deadline <= starts_at),
  check (place_id is not null or nullif(btrim(place_label), '') is not null)
);

create table public.event_attendance (
  event_id uuid not null references public.events(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  status public.attendance_status not null default 'undecided',
  note text check (note is null or char_length(note) <= 300),
  responded_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, profile_id)
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 10000),
  pinned boolean not null default false,
  published_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.videos (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 180),
  category public.video_category not null,
  source_url text not null,
  youtube_id text not null check (youtube_id ~ '^[A-Za-z0-9_-]{6,20}$'),
  check (
    source_url ~ ('^https://youtu\.be/' || youtube_id || '([?/#]|$)') or
    source_url ~ (
      '^https://((www|m|music)\.)?youtube\.com/watch\?([^#]*&)?v=' ||
      youtube_id || '([&#]|$)'
    ) or
    source_url ~ (
      '^https://((www|m|music)\.)?youtube\.com/(shorts|embed|live)/' ||
      youtube_id || '([?/#]|$)'
    )
  ),
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  like_count integer not null default 0 check (like_count >= 0),
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.video_likes (
  video_id uuid not null references public.videos(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (video_id, profile_id)
);

create table public.video_comments (
  id bigint generated always as identity primary key,
  video_id uuid not null references public.videos(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  timestamp_seconds integer not null default 0 check (timestamp_seconds >= 0),
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  entity_table text not null,
  entity_id text not null,
  action text not null check (action in ('insert', 'update', 'delete')),
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create table public.operation_assignments (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location text,
  memo text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table public.homecoming_contacts (
  id uuid primary key default gen_random_uuid(),
  senior_name text not null,
  generation smallint check (generation > 0),
  phone text not null,
  assigned_to uuid references public.profiles(id) on delete set null,
  contact_status text not null default 'pending'
    check (contact_status in ('pending', 'contacted', 'confirmed', 'declined')),
  parking_required boolean,
  parking_registered boolean not null default false,
  notes text,
  last_contacted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index profiles_membership_idx on public.profiles (membership_status, generation);
create index profiles_name_idx on public.profiles (name);
create index profile_teams_team_idx on public.profile_teams (team_id, profile_id);
create index leagues_season_idx on public.leagues (season_id, division);
create index events_upcoming_idx on public.events (starts_at, kind)
  where cancelled_at is null;
create index events_season_idx on public.events (season_id, starts_at)
  where cancelled_at is null;
create index events_league_idx on public.events (league_id, starts_at)
  where league_id is not null and cancelled_at is null;
create index events_parent_idx on public.events (parent_event_id)
  where parent_event_id is not null;
create index attendance_profile_idx on public.event_attendance (profile_id, updated_at desc);
create index attendance_event_status_idx on public.event_attendance (event_id, status);
create index announcements_feed_idx on public.announcements (pinned desc, published_at desc);
create index videos_feed_idx on public.videos (category, created_at desc);
create index videos_uploader_idx on public.videos (uploaded_by, created_at desc);
create index video_likes_profile_idx on public.video_likes (profile_id, created_at desc);
create index video_comments_video_idx on public.video_comments (video_id, timestamp_seconds, created_at);
create index audit_entity_idx on public.audit_logs (entity_table, entity_id, created_at desc);
create index audit_actor_idx on public.audit_logs (actor_id, created_at desc);
create index operations_profile_time_idx
  on public.operation_assignments (profile_id, starts_at);
create index homecoming_assignee_status_idx
  on public.homecoming_contacts (assigned_to, contact_status, generation);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger events_set_updated_at before update of
  title, kind, starts_at, ends_at, season_id, league_id, place_id,
  place_label, court, target_team, opponent, uniform_color, memo, capacity,
  response_enabled, response_deadline, recurrence_rule, parent_event_id,
  updated_by, cancelled_at
on public.events for each row execute function public.set_updated_at();
create trigger attendance_set_updated_at before update on public.event_attendance
for each row execute function public.set_updated_at();
create trigger announcements_set_updated_at before update on public.announcements
for each row execute function public.set_updated_at();
create trigger videos_set_updated_at before update on public.videos
for each row execute function public.set_updated_at();
create trigger video_comments_set_updated_at before update on public.video_comments
for each row execute function public.set_updated_at();
create trigger operation_assignments_set_updated_at before update on public.operation_assignments
for each row execute function public.set_updated_at();
create trigger homecoming_contacts_set_updated_at before update on public.homecoming_contacts
for each row execute function public.set_updated_at();

create or replace function public.expand_weekly_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  occurrence_count integer;
begin
  if new.parent_event_id is not null
    or new.recurrence_rule ->> 'frequency' is distinct from 'weekly' then
    return new;
  end if;

  occurrence_count := least(
    greatest(coalesce((new.recurrence_rule ->> 'count')::integer, 12), 1),
    24
  );

  insert into public.events (
    season_id, league_id, title, kind, starts_at, ends_at, place_id,
    place_label, court, target_team, opponent, uniform_color, memo, capacity,
    response_enabled, response_deadline, recurrence_rule, parent_event_id,
    created_by, updated_by
  )
  select
    new.season_id, new.league_id, new.title, new.kind,
    new.starts_at + (series.week_no * interval '7 days'),
    new.ends_at + (series.week_no * interval '7 days'),
    new.place_id, new.place_label, new.court, new.target_team, new.opponent,
    new.uniform_color, new.memo, new.capacity, new.response_enabled,
    new.response_deadline + (series.week_no * interval '7 days'),
    null, new.id, new.created_by, new.updated_by
  from generate_series(1, occurrence_count - 1) as series(week_no);

  return new;
end;
$$;

create trigger events_expand_weekly
after insert on public.events
for each row execute function public.expand_weekly_event();

create or replace function public.is_encba_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.is_admin from public.profiles p where p.id = (select auth.uid())),
    false
  );
$$;

revoke all on function public.is_encba_admin() from public;
grant execute on function public.is_encba_admin() to authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  allowlist_enabled boolean;
  allowed_member public.member_allowlist%rowtype;
begin
  select coalesce((value #>> '{}')::boolean, false)
    into allowlist_enabled
    from public.app_settings
    where key = 'enforce_member_allowlist';

  if allowlist_enabled and not exists (
    select 1 from public.member_allowlist a
    where a.email = new.email and a.consumed_by is null
  ) then
    raise exception 'ENCBA_MEMBER_NOT_ALLOWLISTED';
  end if;

  select * into allowed_member
  from public.member_allowlist a
  where a.email = new.email and a.consumed_by is null;

  insert into public.profiles (
    id, email, name, student_year, generation, phone, position, jersey_number
  ) values (
    new.id,
    new.email,
    coalesce(allowed_member.name, nullif(btrim(new.raw_user_meta_data ->> 'name'), ''), 'ENCBA 부원'),
    coalesce(allowed_member.student_year, (new.raw_user_meta_data ->> 'student_year')::smallint, 0),
    coalesce(allowed_member.generation, (new.raw_user_meta_data ->> 'generation')::smallint, 1),
    coalesce(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'position', '미정'),
    coalesce((new.raw_user_meta_data ->> 'jersey_number')::smallint, 0)
  );

  insert into public.profile_teams (profile_id, team_id)
  select new.id, t.id
  from public.teams t
  where t.code = any(coalesce(allowed_member.team_codes, array['ENCBA']::text[]));

  update public.member_allowlist
  set consumed_by = new.id, consumed_at = now()
  where email = new.email and consumed_by is null;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

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
      or new.membership_status is distinct from old.membership_status
      or new.generation is distinct from old.generation
      or new.student_year is distinct from old.student_year
      or new.badge is distinct from old.badge
      or new.email is distinct from old.email then
      raise exception 'ENCBA_PROFILE_AUTHORIZATION_FIELDS_ARE_ADMIN_ONLY';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_protect_authorization
before update on public.profiles
for each row execute function public.protect_profile_authorization();

create or replace function public.enforce_attendance_deadline()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  deadline timestamptz;
  enabled boolean;
  target_event_id uuid;
begin
  if public.is_encba_admin() then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  target_event_id := case
    when tg_op = 'DELETE' then old.event_id
    else new.event_id
  end;
  select e.response_deadline, e.response_enabled
    into deadline, enabled
    from public.events e where e.id = target_event_id;
  if not coalesce(enabled, false) or now() >= deadline then
    raise exception 'ENCBA_ATTENDANCE_CLOSED';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger attendance_enforce_deadline
before insert or update or delete on public.event_attendance
for each row execute function public.enforce_attendance_deadline();

create or replace function public.protect_attendance_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.event_id is distinct from old.event_id
    or new.profile_id is distinct from old.profile_id then
    raise exception 'ENCBA_ATTENDANCE_IDENTITY_IS_IMMUTABLE';
  end if;
  return new;
end;
$$;

create trigger attendance_protect_identity
before update on public.event_attendance
for each row execute function public.protect_attendance_identity();

create or replace function public.sync_event_attending_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_event_id uuid;
  count_delta integer;
begin
  target_event_id := case
    when tg_op = 'DELETE' then old.event_id
    else new.event_id
  end;
  count_delta := case
    when tg_op = 'INSERT' and new.status = 'attending' then 1
    when tg_op = 'DELETE' and old.status = 'attending' then -1
    when tg_op = 'UPDATE' then
      (case when new.status = 'attending' then 1 else 0 end) -
      (case when old.status = 'attending' then 1 else 0 end)
    else 0
  end;

  update public.events
  set attending_count = greatest(attending_count + count_delta, 0)
  where id = target_event_id;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger attendance_sync_count
after insert or update or delete on public.event_attendance
for each row execute function public.sync_event_attending_count();

create or replace function public.sync_video_like_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_video_id uuid;
  count_delta integer;
begin
  target_video_id := case
    when tg_op = 'DELETE' then old.video_id
    else new.video_id
  end;
  count_delta := case when tg_op = 'DELETE' then -1 else 1 end;
  update public.videos
  set like_count = greatest(like_count + count_delta, 0)
  where id = target_video_id;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger video_likes_sync_count
after insert or delete on public.video_likes
for each row execute function public.sync_video_like_count();

create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_id text;
begin
  row_id := case
    when tg_op = 'DELETE' then to_jsonb(old) ->> 'id'
    else to_jsonb(new) ->> 'id'
  end;
  insert into public.audit_logs (
    actor_id, entity_table, entity_id, action, old_data, new_data
  ) values (
    (select auth.uid()), tg_table_name, row_id, lower(tg_op),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end
  );
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger events_audit after insert or delete or update of
  title, kind, starts_at, ends_at, place_id, place_label, court, target_team,
  opponent, uniform_color, memo, capacity, response_enabled,
  response_deadline, recurrence_rule, cancelled_at
on public.events
for each row execute function public.write_audit_log();
create trigger announcements_audit after insert or update or delete on public.announcements
for each row execute function public.write_audit_log();
create trigger videos_audit after insert or delete or update of
  title, category, source_url, youtube_id, duration_seconds, uploaded_by
on public.videos
for each row execute function public.write_audit_log();
create trigger operation_assignments_audit
after insert or update or delete on public.operation_assignments
for each row execute function public.write_audit_log();
create trigger homecoming_contacts_audit
after insert or update or delete on public.homecoming_contacts
for each row execute function public.write_audit_log();

alter table public.app_settings enable row level security;
alter table public.member_allowlist enable row level security;
alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.profile_teams enable row level security;
alter table public.seasons enable row level security;
alter table public.leagues enable row level security;
alter table public.places enable row level security;
alter table public.events enable row level security;
alter table public.event_attendance enable row level security;
alter table public.announcements enable row level security;
alter table public.videos enable row level security;
alter table public.video_likes enable row level security;
alter table public.video_comments enable row level security;
alter table public.audit_logs enable row level security;
alter table public.operation_assignments enable row level security;
alter table public.homecoming_contacts enable row level security;

create or replace function public.can_view_event(requested_team text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    requested_team = '전체'
    or public.is_encba_admin()
    or exists (
      select 1
      from public.profile_teams pt
      join public.teams t on t.id = pt.team_id
      where pt.profile_id = (select auth.uid())
        and t.code = case
          when requested_team like 'ENCBA%' then 'ENCBA'
          else requested_team
        end
    );
$$;

revoke all on function public.can_view_event(text) from public;
grant execute on function public.can_view_event(text) to authenticated;

create or replace function public.can_access_event(requested_event uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.events e
    where e.id = requested_event
      and public.can_view_event(e.target_team)
  );
$$;

revoke all on function public.can_access_event(uuid) from public;
grant execute on function public.can_access_event(uuid) to authenticated;

create policy profiles_read_team on public.profiles for select to authenticated
using (true);
create policy profiles_update_self_or_admin on public.profiles for update to authenticated
using ((select auth.uid()) = id or (select public.is_encba_admin()))
with check ((select auth.uid()) = id or (select public.is_encba_admin()));

create policy teams_read on public.teams for select to authenticated using (true);
create policy profile_teams_read on public.profile_teams for select to authenticated using (true);
create policy profile_teams_admin_all on public.profile_teams for all to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));

create policy settings_admin_read on public.app_settings for select to authenticated
using ((select public.is_encba_admin()));
create policy settings_admin_write on public.app_settings for all to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));
create policy allowlist_admin_all on public.member_allowlist for all to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));

create policy seasons_read on public.seasons for select to authenticated using (true);
create policy seasons_admin_all on public.seasons for all to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));
create policy leagues_read on public.leagues for select to authenticated using (true);
create policy leagues_admin_all on public.leagues for all to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));
create policy places_read on public.places for select to authenticated using (is_active);
create policy places_admin_all on public.places for all to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));

create policy events_read on public.events for select to authenticated
using ((select public.can_view_event(target_team)));
create policy events_admin_insert on public.events for insert to authenticated
with check (
  (select public.is_encba_admin()) and
  created_by = (select auth.uid()) and
  updated_by = (select auth.uid())
);
create policy events_admin_update on public.events for update to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));
create policy events_admin_delete on public.events for delete to authenticated
using ((select public.is_encba_admin()));

create policy attendance_read on public.event_attendance for select to authenticated
using (profile_id = (select auth.uid()) or (select public.is_encba_admin()));
create policy attendance_insert on public.event_attendance for insert to authenticated
with check (
  (select public.is_encba_admin()) or (
    profile_id = (select auth.uid()) and
    (select public.can_access_event(event_id))
  )
);
create policy attendance_update on public.event_attendance for update to authenticated
using (
  (select public.is_encba_admin()) or (
    profile_id = (select auth.uid()) and
    (select public.can_access_event(event_id))
  )
)
with check (
  (select public.is_encba_admin()) or (
    profile_id = (select auth.uid()) and
    (select public.can_access_event(event_id))
  )
);
create policy attendance_delete on public.event_attendance for delete to authenticated
using ((select public.is_encba_admin()));

create policy announcements_read on public.announcements for select to authenticated using (true);
create policy announcements_admin_all on public.announcements for all to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));

create policy videos_read on public.videos for select to authenticated using (true);
create policy videos_insert on public.videos for insert to authenticated
with check (
  uploaded_by = (select auth.uid()) and
  (category = 'shared' or (select public.is_encba_admin()))
);
create policy videos_update on public.videos for update to authenticated
using (
  (select public.is_encba_admin()) or
  (uploaded_by = (select auth.uid()) and category = 'shared')
)
with check (
  (select public.is_encba_admin()) or
  (uploaded_by = (select auth.uid()) and category = 'shared')
);
create policy videos_delete on public.videos for delete to authenticated
using (
  (select public.is_encba_admin()) or
  (uploaded_by = (select auth.uid()) and category = 'shared')
);

create policy video_likes_read on public.video_likes for select to authenticated
using (profile_id = (select auth.uid()) or (select public.is_encba_admin()));
create policy video_likes_insert on public.video_likes for insert to authenticated
with check (profile_id = (select auth.uid()));
create policy video_likes_delete on public.video_likes for delete to authenticated
using (profile_id = (select auth.uid()));

create policy video_comments_read on public.video_comments for select to authenticated using (true);
create policy video_comments_insert on public.video_comments for insert to authenticated
with check (profile_id = (select auth.uid()));
create policy video_comments_update on public.video_comments for update to authenticated
using (profile_id = (select auth.uid()) or (select public.is_encba_admin()))
with check (profile_id = (select auth.uid()) or (select public.is_encba_admin()));
create policy video_comments_delete on public.video_comments for delete to authenticated
using (profile_id = (select auth.uid()) or (select public.is_encba_admin()));

create policy audit_read on public.audit_logs for select to authenticated
using (
  (select public.is_encba_admin()) or
  entity_table in ('announcements', 'videos') or (
    entity_table = 'events' and
    (old_data is null or (select public.can_view_event(old_data ->> 'target_team'))) and
    (new_data is null or (select public.can_view_event(new_data ->> 'target_team')))
  )
);

create policy operations_read_own_or_admin on public.operation_assignments
for select to authenticated
using (profile_id = (select auth.uid()) or (select public.is_encba_admin()));
create policy operations_admin_all on public.operation_assignments
for all to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));
create policy homecoming_admin_all on public.homecoming_contacts
for all to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));

grant usage on schema public to authenticated;
grant select on public.profiles, public.teams, public.profile_teams, public.seasons,
  public.leagues, public.places, public.events, public.event_attendance,
  public.announcements, public.videos, public.video_likes,
  public.video_comments, public.audit_logs to authenticated;
grant insert, update, delete on public.profile_teams, public.seasons,
  public.leagues, public.places, public.events, public.event_attendance,
  public.announcements, public.video_likes,
  public.video_comments, public.operation_assignments,
  public.homecoming_contacts to authenticated;
grant insert, delete on public.videos to authenticated;
grant select on public.operation_assignments, public.homecoming_contacts
  to authenticated;
grant update on public.profiles to authenticated;
grant select, insert, update, delete on public.app_settings,
  public.member_allowlist to authenticated;
grant usage, select on all sequences in schema public to authenticated;

revoke update on public.events from authenticated;
grant update (
  title, kind, starts_at, ends_at, season_id, league_id, place_id, place_label,
  court, target_team, opponent, uniform_color, memo, capacity,
  response_enabled, response_deadline, recurrence_rule, parent_event_id,
  updated_by, cancelled_at, attending_count
) on public.events to authenticated;
revoke update on public.videos from authenticated;
grant update (title, category, source_url, youtube_id, duration_seconds)
on public.videos to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy avatars_read_team on storage.objects for select to authenticated
using (bucket_id = 'avatars');
create policy avatars_insert_own on storage.objects for insert to authenticated
with check (
  bucket_id = 'avatars' and
  (storage.foldername(name))[1] = (select auth.uid())::text
);
create policy avatars_update_own on storage.objects for update to authenticated
using (
  bucket_id = 'avatars' and
  (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'avatars' and
  (storage.foldername(name))[1] = (select auth.uid())::text
);
create policy avatars_delete_own on storage.objects for delete to authenticated
using (
  bucket_id = 'avatars' and
  (storage.foldername(name))[1] = (select auth.uid())::text
);

commit;
