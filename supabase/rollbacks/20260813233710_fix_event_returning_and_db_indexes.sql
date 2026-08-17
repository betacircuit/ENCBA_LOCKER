begin;

drop policy if exists events_read on public.events;
create policy events_read on public.events
for select to authenticated
using ((select public.can_access_event(id)));

create index if not exists attendance_event_choice_idx
  on public.event_attendance (event_id, choice);

drop policy if exists announcement_event_links_read
  on public.announcement_event_links;
drop policy if exists announcement_event_links_insert
  on public.announcement_event_links;
drop policy if exists announcement_event_links_update
  on public.announcement_event_links;
drop policy if exists announcement_event_links_delete
  on public.announcement_event_links;

create policy announcement_event_links_read
on public.announcement_event_links
for select to authenticated
using ((select public.can_access_event(event_id)));

create policy announcement_event_links_manage
on public.announcement_event_links
for all to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));

commit;
