-- Expand first: old clients keep writing rows that default to all members.
alter table public.videos
  add column if not exists audience_type text not null default 'all',
  add column if not exists audience_values text[] not null default '{}'::text[];

alter table public.events
  add column if not exists map_reference text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'videos_audience_type_check'
      and conrelid = 'public.videos'::regclass
  ) then
    alter table public.videos add constraint videos_audience_type_check
      check (audience_type in ('all', 'position', 'freshman', 'student_year'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'videos_audience_values_check'
      and conrelid = 'public.videos'::regclass
  ) then
    alter table public.videos add constraint videos_audience_values_check check (
      (audience_type in ('all', 'freshman') and cardinality(audience_values) = 0)
      or (audience_type in ('position', 'student_year') and cardinality(audience_values) > 0)
    );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'events_map_reference_length_check'
      and conrelid = 'public.events'::regclass
  ) then
    alter table public.events add constraint events_map_reference_length_check
      check (map_reference is null or char_length(map_reference) between 1 and 2000);
  end if;
end $$;

drop policy if exists videos_read on public.videos;
create policy videos_read on public.videos for select to authenticated
using (
  category <> 'shared'
  or uploaded_by = (select auth.uid())
  or (select public.is_encba_admin())
  or audience_type = 'all'
  or exists (
    select 1
    from public.profiles viewer
    where viewer.id = (select auth.uid())
      and viewer.is_active
      and (
        (audience_type = 'position' and viewer.position = any(audience_values))
        or (
          audience_type = 'freshman'
          and viewer.joined_year = extract(year from timezone('Asia/Seoul', now()))::smallint
        )
        or (
          audience_type = 'student_year'
          and lpad(viewer.student_year::text, 2, '0') = any(audience_values)
        )
      )
  )
);

-- Prevent guessed video ids from exposing or accepting child rows.
drop policy if exists video_comments_read on public.video_comments;
create policy video_comments_read on public.video_comments for select to authenticated
using (exists (select 1 from public.videos video where video.id = video_id));

drop policy if exists video_comments_insert on public.video_comments;
create policy video_comments_insert on public.video_comments for insert to authenticated
with check (
  profile_id = (select auth.uid())
  and exists (select 1 from public.videos video where video.id = video_id)
);

drop policy if exists video_likes_insert on public.video_likes;
create policy video_likes_insert on public.video_likes for insert to authenticated
with check (
  profile_id = (select auth.uid())
  and exists (select 1 from public.videos video where video.id = video_id)
);

revoke update on public.videos from authenticated;
grant update (
  title, category, source_url, youtube_id, source_type,
  quarter_1_url, quarter_2_url, quarter_3_url, quarter_4_url, duration_seconds,
  audience_type, audience_values
) on public.videos to authenticated;

revoke update on public.events from authenticated;
grant update (
  title, kind, starts_at, ends_at, season_id, league_id, place_id, place_label,
  court, target_team, opponent, opponents, uniform_colors, memo, capacity,
  response_enabled, response_deadline, recurrence_rule, poll_options,
  visibility, parent_event_id, updated_by, cancelled_at, attending_count,
  map_reference
) on public.events to authenticated;

drop trigger if exists events_audit on public.events;
create trigger events_audit after insert or delete or update of
  title, kind, starts_at, ends_at, place_id, place_label, court, target_team,
  opponent, opponents, uniform_colors, memo, capacity, response_enabled,
  response_deadline, recurrence_rule, poll_options, visibility, map_reference,
  cancelled_at
on public.events
for each row execute function public.write_audit_log();

update public.events
set opponents = array_replace(opponents, '농구부', '서울대 농구부'),
    opponent = replace(replace(opponent, '농구부', '서울대 농구부'), '새턴OB', '새턴')
where opponents && array['농구부', '새턴OB']::text[]
   or opponent like '%농구부%'
   or opponent like '%새턴OB%';

update public.events
set opponents = array_replace(opponents, '새턴OB', '새턴')
where opponents && array['새턴OB']::text[];
