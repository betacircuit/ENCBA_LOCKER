-- Expand-only migration. Existing video/comment readers remain valid.
create table public.video_review_players (
  video_id uuid not null references public.videos(id) on delete cascade,
  member_allowlist_id bigint not null
    references public.member_allowlist(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (video_id, member_allowlist_id)
);

create table public.video_comment_targets (
  comment_id bigint not null references public.video_comments(id) on delete cascade,
  member_allowlist_id bigint not null
    references public.member_allowlist(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, member_allowlist_id)
);

create index video_review_players_member_idx
  on public.video_review_players (member_allowlist_id);
create index video_comment_targets_member_idx
  on public.video_comment_targets (member_allowlist_id);

alter table public.video_review_players enable row level security;
alter table public.video_comment_targets enable row level security;

-- These tables are intentionally not exposed through PostgREST. Access goes
-- through the authenticated RPCs below so allowlist names stay private.
revoke all on public.video_review_players from anon, authenticated;
revoke all on public.video_comment_targets from anon, authenticated;

create or replace function public.set_video_review_players(
  requested_video_id uuid,
  requested_directory_ids text[] default '{}'::text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  expected_count integer;
  resolved_count integer;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if coalesce(cardinality(requested_directory_ids), 0) > 30 then
    raise exception 'too many review players' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.videos video
    where video.id = requested_video_id
      and video.category = 'review'
  ) then
    raise exception 'review video not found' using errcode = 'P0002';
  end if;

  select count(*) into expected_count
  from (
    select distinct btrim(directory_id) as directory_id
    from unnest(coalesce(requested_directory_ids, '{}'::text[])) directory_id
    where nullif(btrim(directory_id), '') is not null
  ) requested;

  select count(*) into resolved_count
  from (
    select distinct allowed.id
    from (
      select distinct btrim(directory_id) as directory_id
      from unnest(coalesce(requested_directory_ids, '{}'::text[])) directory_id
      where nullif(btrim(directory_id), '') is not null
    ) requested
    join public.member_allowlist allowed on
      allowed.id = case
        when requested.directory_id ~ '^allowlist:[0-9]+$'
          then substring(requested.directory_id from 11)::bigint
        else null
      end
      or allowed.consumed_by = case
        when requested.directory_id ~
          '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
          then requested.directory_id::uuid
        else null
      end
  ) resolved;

  if resolved_count <> expected_count then
    raise exception 'unknown member in review player selection'
      using errcode = '22023';
  end if;

  delete from public.video_review_players
  where video_id = requested_video_id;

  insert into public.video_review_players (video_id, member_allowlist_id)
  select requested_video_id, allowed.id
  from (
    select distinct btrim(directory_id) as directory_id
    from unnest(coalesce(requested_directory_ids, '{}'::text[])) directory_id
    where nullif(btrim(directory_id), '') is not null
  ) requested
  join public.member_allowlist allowed on
    allowed.id = case
      when requested.directory_id ~ '^allowlist:[0-9]+$'
        then substring(requested.directory_id from 11)::bigint
      else null
    end
    or allowed.consumed_by = case
      when requested.directory_id ~
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
        then requested.directory_id::uuid
      else null
    end
  on conflict do nothing;
end;
$$;

create or replace function public.list_video_review_players(
  requested_video_ids uuid[]
)
returns table (video_id uuid, directory_id text, name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if coalesce(cardinality(requested_video_ids), 0) > 50 then
    raise exception 'too many videos requested' using errcode = '22023';
  end if;

  return query
  select
    link.video_id,
    coalesce(
      allowed.consumed_by::text,
      'allowlist:' || allowed.id::text
    ) as directory_id,
    coalesce(profile.display_name, allowed.name) as name
  from public.video_review_players link
  join public.videos video on video.id = link.video_id
  join public.member_allowlist allowed on allowed.id = link.member_allowlist_id
  left join public.profiles profile on profile.id = allowed.consumed_by
  where link.video_id = any(coalesce(requested_video_ids, '{}'::uuid[]))
    and video.category = 'review'
  order by link.video_id, allowed.student_year, allowed.name;
end;
$$;

create or replace function public.set_video_comment_targets(
  requested_comment_id bigint,
  requested_directory_ids text[] default '{}'::text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  expected_count integer;
  resolved_count integer;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if coalesce(cardinality(requested_directory_ids), 0) > 10 then
    raise exception 'too many feedback targets' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.video_comments comment
    join public.videos video on video.id = comment.video_id
    where comment.id = requested_comment_id
      and video.category = 'review'
      and (
        comment.profile_id = (select auth.uid())
        or (select public.is_encba_admin())
      )
  ) then
    raise exception 'comment not editable' using errcode = '42501';
  end if;

  select count(*) into expected_count
  from (
    select distinct btrim(directory_id) as directory_id
    from unnest(coalesce(requested_directory_ids, '{}'::text[])) directory_id
    where nullif(btrim(directory_id), '') is not null
  ) requested;

  select count(*) into resolved_count
  from (
    select distinct allowed.id
    from (
      select distinct btrim(directory_id) as directory_id
      from unnest(coalesce(requested_directory_ids, '{}'::text[])) directory_id
      where nullif(btrim(directory_id), '') is not null
    ) requested
    join public.member_allowlist allowed on
      allowed.id = case
        when requested.directory_id ~ '^allowlist:[0-9]+$'
          then substring(requested.directory_id from 11)::bigint
        else null
      end
      or allowed.consumed_by = case
        when requested.directory_id ~
          '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
          then requested.directory_id::uuid
        else null
      end
  ) resolved;

  if resolved_count <> expected_count then
    raise exception 'unknown member in feedback target selection'
      using errcode = '22023';
  end if;

  delete from public.video_comment_targets
  where comment_id = requested_comment_id;

  insert into public.video_comment_targets (comment_id, member_allowlist_id)
  select requested_comment_id, allowed.id
  from (
    select distinct btrim(directory_id) as directory_id
    from unnest(coalesce(requested_directory_ids, '{}'::text[])) directory_id
    where nullif(btrim(directory_id), '') is not null
  ) requested
  join public.member_allowlist allowed on
    allowed.id = case
      when requested.directory_id ~ '^allowlist:[0-9]+$'
        then substring(requested.directory_id from 11)::bigint
      else null
    end
    or allowed.consumed_by = case
      when requested.directory_id ~
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
        then requested.directory_id::uuid
      else null
    end
  on conflict do nothing;
end;
$$;

create or replace function public.list_video_comment_targets(
  requested_video_id uuid
)
returns table (comment_id bigint, directory_id text, name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  return query
  select
    target.comment_id,
    coalesce(
      allowed.consumed_by::text,
      'allowlist:' || allowed.id::text
    ) as directory_id,
    coalesce(profile.display_name, allowed.name) as name
  from public.video_comment_targets target
  join public.video_comments comment on comment.id = target.comment_id
  join public.videos video on video.id = comment.video_id
  join public.member_allowlist allowed on allowed.id = target.member_allowlist_id
  left join public.profiles profile on profile.id = allowed.consumed_by
  where comment.video_id = requested_video_id
    and video.category = 'review'
  order by target.comment_id, allowed.student_year, allowed.name;
end;
$$;

revoke all on function public.set_video_review_players(uuid, text[]) from public, anon;
revoke all on function public.list_video_review_players(uuid[]) from public, anon;
revoke all on function public.set_video_comment_targets(bigint, text[]) from public, anon;
revoke all on function public.list_video_comment_targets(uuid) from public, anon;

grant execute on function public.set_video_review_players(uuid, text[]) to authenticated;
grant execute on function public.list_video_review_players(uuid[]) to authenticated;
grant execute on function public.set_video_comment_targets(bigint, text[]) to authenticated;
grant execute on function public.list_video_comment_targets(uuid) to authenticated;

analyze public.video_review_players;
analyze public.video_comment_targets;
