begin;

alter table public.video_comments
  add column if not exists end_timestamp_seconds integer;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'video_comments_end_timestamp_seconds_check'
      and conrelid = 'public.video_comments'::regclass
  ) then
    alter table public.video_comments
      add constraint video_comments_end_timestamp_seconds_check
      check (
        end_timestamp_seconds is null
        or (
          timestamp_seconds is not null
          and end_timestamp_seconds >= timestamp_seconds
        )
      );
  end if;
end
$$;

grant insert (end_timestamp_seconds) on public.video_comments to authenticated;
grant update (end_timestamp_seconds) on public.video_comments to authenticated;

analyze public.video_comments;

commit;
