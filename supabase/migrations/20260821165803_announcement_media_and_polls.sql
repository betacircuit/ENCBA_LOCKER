begin;

create schema if not exists private;

create or replace function public.is_valid_announcement_poll(options text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    cardinality(options) = 0
    or (
      cardinality(options) between 2 and 8
      and not exists (
        select 1
        from unnest(options) as option(value)
        where char_length(btrim(option.value)) not between 1 and 60
      )
      and (
        select count(*) = count(distinct lower(btrim(option.value)))
        from unnest(options) as option(value)
      )
    ),
    false
  );
$$;

revoke all on function public.is_valid_announcement_poll(text[]) from public;
grant execute on function public.is_valid_announcement_poll(text[])
to authenticated;

alter table public.announcements
  add column if not exists image_url text,
  add column if not exists poll_options text[] not null default '{}'::text[];

alter table public.announcements
  drop constraint if exists announcements_poll_options_valid,
  add constraint announcements_poll_options_valid
  check (public.is_valid_announcement_poll(poll_options));

create table if not exists public.announcement_poll_votes (
  announcement_id uuid not null
    references public.announcements(id) on delete cascade,
  profile_id uuid not null
    references public.profiles(id) on delete cascade,
  option_index smallint not null check (option_index >= 0),
  voted_at timestamptz not null default now(),
  primary key (announcement_id, profile_id)
);

create index if not exists announcement_poll_votes_count_idx
  on public.announcement_poll_votes (announcement_id, option_index);

alter table public.announcement_poll_votes enable row level security;

drop policy if exists announcement_poll_votes_read on public.announcement_poll_votes;
create policy announcement_poll_votes_read
on public.announcement_poll_votes
for select to authenticated
using (true);

drop policy if exists announcement_poll_votes_insert_own
on public.announcement_poll_votes;
create policy announcement_poll_votes_insert_own
on public.announcement_poll_votes
for insert to authenticated
with check (
  profile_id = (select auth.uid())
  and exists (
    select 1
    from public.announcements as announcement
    where announcement.id = announcement_id
      and option_index < cardinality(announcement.poll_options)
  )
);

drop policy if exists announcement_poll_votes_update_own
on public.announcement_poll_votes;
create policy announcement_poll_votes_update_own
on public.announcement_poll_votes
for update to authenticated
using (profile_id = (select auth.uid()))
with check (
  profile_id = (select auth.uid())
  and exists (
    select 1
    from public.announcements as announcement
    where announcement.id = announcement_id
      and option_index < cardinality(announcement.poll_options)
  )
);

grant select, insert, update on public.announcement_poll_votes to authenticated;

create or replace function private.clear_changed_announcement_poll_votes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.poll_options is distinct from old.poll_options then
    delete from public.announcement_poll_votes
    where announcement_id = new.id;
  end if;
  return new;
end;
$$;

revoke all on function private.clear_changed_announcement_poll_votes()
from public, anon, authenticated;

drop trigger if exists announcements_clear_changed_poll_votes
on public.announcements;
create trigger announcements_clear_changed_poll_votes
after update of poll_options on public.announcements
for each row
execute function private.clear_changed_announcement_poll_votes();

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'announcement-media',
  'announcement-media',
  true,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists announcement_media_read on storage.objects;
create policy announcement_media_read
on storage.objects
for select to anon, authenticated
using (bucket_id = 'announcement-media');

drop policy if exists announcement_media_insert_admin on storage.objects;
create policy announcement_media_insert_admin
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'announcement-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (select public.is_encba_admin())
);

drop policy if exists announcement_media_update_admin on storage.objects;
create policy announcement_media_update_admin
on storage.objects
for update to authenticated
using (
  bucket_id = 'announcement-media'
  and (select public.is_encba_admin())
)
with check (
  bucket_id = 'announcement-media'
  and (select public.is_encba_admin())
);

drop policy if exists announcement_media_delete_admin on storage.objects;
create policy announcement_media_delete_admin
on storage.objects
for delete to authenticated
using (
  bucket_id = 'announcement-media'
  and (select public.is_encba_admin())
);

notify pgrst, 'reload schema';

commit;
