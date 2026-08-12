begin;

alter table public.profiles
  add column if not exists joined_year smallint,
  add column if not exists leadership_role text not null default 'member';

alter table public.member_allowlist
  add column if not exists joined_year smallint,
  add column if not exists leadership_role text not null default 'member',
  add column if not exists phone text not null default '',
  add column if not exists position text not null default '미정',
  add column if not exists jersey_number smallint not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_joined_year_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles add constraint profiles_joined_year_check
      check (joined_year is null or joined_year between 1977 and 2100);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_leadership_role_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles add constraint profiles_leadership_role_check
      check (leadership_role in ('member', 'manager', 'captain', 'admin'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'allowlist_joined_year_check'
      and conrelid = 'public.member_allowlist'::regclass
  ) then
    alter table public.member_allowlist add constraint allowlist_joined_year_check
      check (joined_year is null or joined_year between 1977 and 2100);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'allowlist_leadership_role_check'
      and conrelid = 'public.member_allowlist'::regclass
  ) then
    alter table public.member_allowlist add constraint allowlist_leadership_role_check
      check (leadership_role in ('member', 'manager', 'captain', 'admin'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'allowlist_position_check'
      and conrelid = 'public.member_allowlist'::regclass
  ) then
    alter table public.member_allowlist add constraint allowlist_position_check
      check (position in ('PG', 'SG', 'SF', 'PF', 'C', '미정'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'allowlist_jersey_number_check'
      and conrelid = 'public.member_allowlist'::regclass
  ) then
    alter table public.member_allowlist add constraint allowlist_jersey_number_check
      check (jersey_number between 0 and 99);
  end if;
end $$;

update public.member_allowlist
set leadership_role = case name
  when '최재원' then 'admin'
  when '임준호' then 'captain'
  when '홍성준' then 'manager'
  else leadership_role
end,
is_admin = name = '최재원',
is_schedule_manager = case when name = '임준호' then true else is_schedule_manager end
where name in ('최재원', '임준호', '홍성준');

update public.profiles
set leadership_role = case name
  when '최재원' then 'admin'
  when '임준호' then 'captain'
  when '홍성준' then 'manager'
  else leadership_role
end,
is_admin = name = '최재원',
is_schedule_manager = case when name = '임준호' then true else is_schedule_manager end
where name in ('최재원', '임준호', '홍성준');

create index if not exists profiles_leadership_active_idx
  on public.profiles (leadership_role, is_active);

create or replace function public.is_encba_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select p.is_admin or p.leadership_role = 'captain'
      from public.profiles p
      where p.id = (select auth.uid()) and p.is_active
    ),
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
    where a.login_name = btrim(new.raw_user_meta_data ->> 'name')
      and a.consumed_by is null
      and a.is_active
  ) then
    raise exception 'ENCBA_MEMBER_NOT_ALLOWLISTED_OR_INACTIVE';
  end if;

  select * into allowed_member
  from public.member_allowlist a
  where a.login_name = btrim(new.raw_user_meta_data ->> 'name')
    and a.consumed_by is null
    and a.is_active;

  insert into public.profiles (
    id, email, name, display_name, student_year, generation, joined_year,
    phone, position, jersey_number, membership_status, badge,
    is_admin, is_schedule_manager, is_active, leadership_role
  ) values (
    new.id,
    new.email,
    allowed_member.name,
    allowed_member.name,
    coalesce(allowed_member.student_year, (new.raw_user_meta_data ->> 'student_year')::smallint, 0),
    coalesce(allowed_member.generation, 1),
    coalesce(allowed_member.joined_year, (new.raw_user_meta_data ->> 'joined_year')::smallint),
    coalesce(nullif(allowed_member.phone, ''), new.raw_user_meta_data ->> 'phone', ''),
    coalesce(nullif(allowed_member.position, ''), new.raw_user_meta_data ->> 'position', '미정'),
    coalesce(nullif(allowed_member.jersey_number, 0), (new.raw_user_meta_data ->> 'jersey_number')::smallint, 0),
    allowed_member.membership_status,
    case allowed_member.membership_status
      when 'military_leave' then '군복무'
      when 'graduated' then '졸업'
      else null
    end,
    allowed_member.is_admin,
    allowed_member.is_schedule_manager,
    true,
    allowed_member.leadership_role
  );

  insert into public.profile_teams (profile_id, team_id)
  select new.id, t.id
  from public.teams t
  where t.code = any(coalesce(allowed_member.team_codes, array['ENCBA']::text[]));

  update public.member_allowlist
  set consumed_by = new.id, consumed_at = now()
  where id = allowed_member.id and consumed_by is null;
  return new;
end;
$$;

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
      or new.is_active is distinct from old.is_active
      or new.membership_status is distinct from old.membership_status
      or new.generation is distinct from old.generation
      or new.joined_year is distinct from old.joined_year
      or new.student_year is distinct from old.student_year
      or new.badge is distinct from old.badge
      or new.is_schedule_manager is distinct from old.is_schedule_manager
      or new.leadership_role is distinct from old.leadership_role
      or new.name is distinct from old.name
      or new.email is distinct from old.email then
      raise exception 'ENCBA_PROFILE_AUTHORIZATION_FIELDS_ARE_ADMIN_ONLY';
    end if;
  end if;
  return new;
end;
$$;

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
    coalesce(p.id::text, 'allowlist:' || a.id::text),
    coalesce(p.display_name, a.name),
    coalesce(p.student_year, a.student_year),
    coalesce(p.generation, a.generation, 1::smallint),
    coalesce(p.joined_year, a.joined_year),
    coalesce(p.membership_status, a.membership_status),
    coalesce(p.is_active, a.is_active),
    coalesce(nullif(p.phone, ''), a.phone, ''),
    coalesce(p.position, a.position, '미정'),
    coalesce(p.jersey_number, a.jersey_number, 0::smallint),
    case when p.id is null then coalesce(a.team_codes, array['ENCBA']::text[])
    else array(
        select t.code
        from public.profile_teams pt
        join public.teams t on t.id = pt.team_id
        where pt.profile_id = p.id
        order by t.code
      ) end,
    coalesce(p.leadership_role, a.leadership_role, 'member')
  from public.member_allowlist a
  left join public.profiles p on p.id = a.consumed_by
  where (select auth.uid()) is not null
    and (
      requested_status = 'all'
      or (requested_status = 'military' and coalesce(p.membership_status, a.membership_status) = 'military_leave')
    )
    and (
      nullif(btrim(requested_query), '') is null
      or coalesce(p.display_name, a.name) ilike '%' || btrim(requested_query) || '%'
      or lpad(coalesce(p.student_year, a.student_year, 0)::text, 2, '0') = regexp_replace(requested_query, '[^0-9]', '', 'g')
    )
  order by coalesce(p.membership_status, a.membership_status) = 'military_leave' desc,
           coalesce(p.display_name, a.name);
$$;

revoke all on function public.list_member_directory(text, text) from public;
grant execute on function public.list_member_directory(text, text) to authenticated;

create or replace function public.admin_update_member(
  requested_directory_id text,
  requested_name text,
  requested_student_year smallint,
  requested_joined_year smallint,
  requested_phone text,
  requested_position text,
  requested_jersey_number smallint,
  requested_membership_status text,
  requested_team_codes text[],
  requested_leadership_role text,
  requested_active boolean
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
    raise exception 'ENCBA_ADMIN_OR_CAPTAIN_REQUIRED';
  end if;
  if nullif(btrim(requested_name), '') is null
    or requested_student_year not between 0 and 99
    or requested_joined_year not between 1977 and 2100
    or requested_position not in ('PG', 'SG', 'SF', 'PF', 'C', '미정')
    or requested_jersey_number not between 0 and 99
    or requested_membership_status not in ('yb', 'ob', 'military_leave', 'graduated', 'inactive')
    or requested_leadership_role not in ('member', 'manager', 'captain', 'admin')
    or cardinality(requested_team_codes) < 1
    or not requested_team_codes <@ array['ENCBA', 'BEN']::text[] then
    raise exception 'ENCBA_INVALID_MEMBER_PROFILE';
  end if;

  if requested_directory_id like 'allowlist:%' then
    update public.member_allowlist
    set name = btrim(requested_name),
        login_name = btrim(requested_name),
        student_year = requested_student_year,
        joined_year = requested_joined_year,
        phone = coalesce(requested_phone, ''),
        position = requested_position,
        jersey_number = requested_jersey_number,
        membership_status = requested_membership_status::public.membership_status,
        team_codes = requested_team_codes,
        leadership_role = requested_leadership_role,
        is_admin = requested_leadership_role = 'admin',
        is_schedule_manager = requested_leadership_role in ('admin', 'captain'),
        is_active = requested_active
    where id = substring(requested_directory_id from 11)::bigint;
    return;
  end if;

  target_profile := requested_directory_id::uuid;
  update public.profiles
  set name = btrim(requested_name),
      display_name = btrim(requested_name),
      student_year = requested_student_year,
      joined_year = requested_joined_year,
      phone = coalesce(requested_phone, ''),
      position = requested_position,
      jersey_number = requested_jersey_number,
      membership_status = requested_membership_status::public.membership_status,
      leadership_role = requested_leadership_role,
      is_admin = requested_leadership_role = 'admin',
      is_schedule_manager = requested_leadership_role in ('admin', 'captain'),
      is_active = requested_active,
      badge = case requested_membership_status
        when 'military_leave' then '군복무'
        when 'graduated' then '졸업'
        else null
      end
  where id = target_profile;

  delete from public.profile_teams where profile_id = target_profile;
  insert into public.profile_teams (profile_id, team_id)
  select target_profile, t.id from public.teams t
  where t.code = any(requested_team_codes);

  update public.member_allowlist
  set name = btrim(requested_name),
      login_name = btrim(requested_name),
      student_year = requested_student_year,
      joined_year = requested_joined_year,
      phone = coalesce(requested_phone, ''),
      position = requested_position,
      jersey_number = requested_jersey_number,
      membership_status = requested_membership_status::public.membership_status,
      team_codes = requested_team_codes,
      leadership_role = requested_leadership_role,
      is_admin = requested_leadership_role = 'admin',
      is_schedule_manager = requested_leadership_role in ('admin', 'captain'),
      is_active = requested_active
  where consumed_by = target_profile;
end;
$$;

revoke all on function public.admin_update_member(
  text, text, smallint, smallint, text, text, smallint, text, text[], text, boolean
) from public;
grant execute on function public.admin_update_member(
  text, text, smallint, smallint, text, text, smallint, text, text[], text, boolean
) to authenticated;

alter table public.videos
  add column if not exists source_type text not null default 'youtube',
  add column if not exists quarter_1_url text,
  add column if not exists quarter_2_url text,
  add column if not exists quarter_3_url text,
  add column if not exists quarter_4_url text,
  alter column youtube_id drop not null,
  drop constraint if exists videos_youtube_id_check,
  drop constraint if exists videos_check;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'videos_source_check'
      and conrelid = 'public.videos'::regclass
  ) then
    alter table public.videos add constraint videos_source_check check (
      (
        source_type = 'youtube'
        and youtube_id ~ '^[A-Za-z0-9_-]{6,20}$'
        and source_url ~ '^https://(www\.|m\.|music\.)?(youtube\.com|youtu\.be)/'
      ) or (
        source_type = 'instagram'
        and youtube_id is null
        and source_url ~ '^https://(www\.)?instagram\.com/reel/[A-Za-z0-9_-]+/?'
      )
    );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'videos_quarter_urls_check'
      and conrelid = 'public.videos'::regclass
  ) then
    alter table public.videos add constraint videos_quarter_urls_check check (
      (quarter_1_url is null or quarter_1_url ~ '^https://')
      and (quarter_2_url is null or quarter_2_url ~ '^https://')
      and (quarter_3_url is null or quarter_3_url ~ '^https://')
      and (quarter_4_url is null or quarter_4_url ~ '^https://')
    );
  end if;
end $$;

drop policy if exists videos_insert on public.videos;
create policy videos_insert on public.videos for insert to authenticated
with check (
  uploaded_by = (select auth.uid()) and
  (category in ('shared', 'review') or (select public.is_encba_admin()))
);

drop policy if exists videos_update on public.videos;
create policy videos_update on public.videos for update to authenticated
using (
  (select public.is_encba_admin()) or
  (uploaded_by = (select auth.uid()) and category in ('shared', 'review'))
)
with check (
  (select public.is_encba_admin()) or
  (uploaded_by = (select auth.uid()) and category in ('shared', 'review'))
);

drop policy if exists videos_delete on public.videos;
create policy videos_delete on public.videos for delete to authenticated
using (
  (select public.is_encba_admin()) or
  (uploaded_by = (select auth.uid()) and category in ('shared', 'review'))
);

revoke update on public.videos from authenticated;
grant update (
  title, category, source_url, youtube_id, source_type,
  quarter_1_url, quarter_2_url, quarter_3_url, quarter_4_url, duration_seconds
) on public.videos to authenticated;

insert into public.videos (
  title, category, source_url, youtube_id, source_type, uploaded_by
)
select reel.title, 'highlight'::public.video_category, reel.url, null, 'instagram', p.id
from (
  values
    ('ENCBA REEL 1', 'https://www.instagram.com/reel/Db2nVhDz4Fq/'),
    ('ENCBA REEL 2', 'https://www.instagram.com/reel/DajgzpRTc4e/'),
    ('ENCBA REEL 3', 'https://www.instagram.com/reel/DZDMprWogCr/'),
    ('ENCBA REEL 4', 'https://www.instagram.com/reel/DXPE0fsEwcm/'),
    ('ENCBA REEL 5', 'https://www.instagram.com/reel/DTnGCB7E50t/')
) as reel(title, url)
cross join lateral (
  select id from public.profiles
  where leadership_role = 'admin' or is_admin
  order by is_admin desc, created_at
  limit 1
) p
where not exists (
  select 1 from public.videos existing where existing.source_url = reel.url
);

create or replace function public.seed_default_highlights_for_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (new.is_admin or new.leadership_role = 'captain') then
    return new;
  end if;
  insert into public.videos (
    title, category, source_url, youtube_id, source_type, uploaded_by
  )
  select reel.title, 'highlight'::public.video_category, reel.url, null, 'instagram', new.id
  from (
    values
      ('ENCBA REEL 1', 'https://www.instagram.com/reel/Db2nVhDz4Fq/'),
      ('ENCBA REEL 2', 'https://www.instagram.com/reel/DajgzpRTc4e/'),
      ('ENCBA REEL 3', 'https://www.instagram.com/reel/DZDMprWogCr/'),
      ('ENCBA REEL 4', 'https://www.instagram.com/reel/DXPE0fsEwcm/'),
      ('ENCBA REEL 5', 'https://www.instagram.com/reel/DTnGCB7E50t/')
  ) as reel(title, url)
  where not exists (
    select 1 from public.videos existing where existing.source_url = reel.url
  );
  return new;
end;
$$;

drop trigger if exists profiles_seed_default_highlights on public.profiles;
create trigger profiles_seed_default_highlights
after insert on public.profiles
for each row execute function public.seed_default_highlights_for_admin();

revoke all on function public.seed_default_highlights_for_admin() from public;

create or replace function public.get_my_attendance_rates()
returns table (training_rate integer, morning_rate integer, game_rate integer)
language sql
stable
security definer
set search_path = ''
as $$
  with answered as (
    select
      case
        when e.kind = 'training' then 'training'
        when e.kind = 'morning' then 'morning'
        else 'game'
      end as bucket,
      a.choice
    from public.event_attendance a
    join public.events e on e.id = a.event_id
    where a.profile_id = (select auth.uid())
      and e.ends_at >= now() - interval '6 months'
      and e.ends_at <= now()
      and e.cancelled_at is null
  )
  select
    coalesce(round(100.0 * count(*) filter (where bucket = 'training' and choice = '참석') /
      nullif(count(*) filter (where bucket = 'training'), 0)), 0)::integer,
    coalesce(round(100.0 * count(*) filter (where bucket = 'morning' and choice = '참석') /
      nullif(count(*) filter (where bucket = 'morning'), 0)), 0)::integer,
    coalesce(round(100.0 * count(*) filter (where bucket = 'game' and choice = '참석') /
      nullif(count(*) filter (where bucket = 'game'), 0)), 0)::integer
  from answered;
$$;

revoke all on function public.get_my_attendance_rates() from public;
grant execute on function public.get_my_attendance_rates() to authenticated;

notify pgrst, 'reload schema';

commit;
