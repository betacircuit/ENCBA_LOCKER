begin;

drop policy if exists announcement_media_delete_admin on storage.objects;
drop policy if exists announcement_media_update_admin on storage.objects;
drop policy if exists announcement_media_insert_admin on storage.objects;
drop policy if exists announcement_media_read on storage.objects;

delete from storage.buckets as bucket
where bucket.id = 'announcement-media'
  and not exists (
    select 1
    from storage.objects as object
    where object.bucket_id = bucket.id
  );

drop trigger if exists announcements_clear_changed_poll_votes
on public.announcements;
drop function if exists private.clear_changed_announcement_poll_votes();

drop table if exists public.announcement_poll_votes;

alter table public.announcements
  drop constraint if exists announcements_poll_options_valid,
  drop column if exists poll_options,
  drop column if exists image_url;

drop function if exists public.is_valid_announcement_poll(text[]);

notify pgrst, 'reload schema';

commit;
