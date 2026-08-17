-- A timestamp only has meaning inside its review quarter.
alter table public.video_comments
  add column if not exists quarter_number smallint;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'video_comments_quarter_number_check'
      and conrelid = 'public.video_comments'::regclass
  ) then
    alter table public.video_comments
      add constraint video_comments_quarter_number_check
      check (quarter_number is null or quarter_number between 1 and 4);
  end if;
end $$;

drop index if exists public.video_comments_video_idx;
create index video_comments_video_idx
  on public.video_comments (
    video_id,
    quarter_number nulls first,
    timestamp_seconds,
    created_at
  );

grant update (quarter_number) on public.video_comments to authenticated;

analyze public.video_comments;
