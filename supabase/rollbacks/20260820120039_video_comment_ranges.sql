begin;

revoke insert (end_timestamp_seconds) on public.video_comments from authenticated;
revoke update (end_timestamp_seconds) on public.video_comments from authenticated;

alter table public.video_comments
  drop constraint if exists video_comments_end_timestamp_seconds_check;

alter table public.video_comments
  drop column if exists end_timestamp_seconds;

analyze public.video_comments;

commit;
