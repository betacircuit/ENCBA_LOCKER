-- Detail screens subscribe only while open, so video edits and removals stay
-- consistent without polling the whole feed.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'videos'
  ) then
    alter publication supabase_realtime add table public.videos;
  end if;
end $$;

alter table public.videos replica identity full;
