-- 새 일정이 등록되면 공지처럼 실시간으로 알림을 띄우기 위해 events도
-- videos/announcements와 같은 방식으로 realtime publication에 추가한다.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'events'
  ) then
    alter publication supabase_realtime add table public.events;
  end if;
end $$;

alter table public.events replica identity full;
