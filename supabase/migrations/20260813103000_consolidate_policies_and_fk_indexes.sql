-- Keep RLS evaluation to one permissive policy per command and add the
-- foreign-key indexes used by joins, cascades, and audit attribution.

create index if not exists announcements_created_by_idx
  on public.announcements (created_by);
create index if not exists announcements_updated_by_idx
  on public.announcements (updated_by);
create index if not exists events_created_by_idx
  on public.events (created_by);
create index if not exists events_updated_by_idx
  on public.events (updated_by);
create index if not exists events_place_id_idx
  on public.events (place_id) where place_id is not null;
create index if not exists event_roster_updated_by_idx
  on public.event_roster (updated_by) where updated_by is not null;
create index if not exists event_strategies_updated_by_idx
  on public.event_strategies (updated_by) where updated_by is not null;
create index if not exists homecoming_campaigns_created_by_idx
  on public.homecoming_campaigns (created_by);
create index if not exists member_allowlist_consumed_by_idx
  on public.member_allowlist (consumed_by) where consumed_by is not null;
create index if not exists operation_assignments_created_by_idx
  on public.operation_assignments (created_by);
create index if not exists video_comments_profile_id_idx
  on public.video_comments (profile_id);

drop policy if exists announcements_admin_all on public.announcements;
create policy announcements_admin_insert on public.announcements
for insert to authenticated
with check ((select public.is_encba_admin()));
create policy announcements_admin_update on public.announcements
for update to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));
create policy announcements_admin_delete on public.announcements
for delete to authenticated
using ((select public.is_encba_admin()));

drop policy if exists settings_admin_read on public.app_settings;
drop policy if exists settings_admin_write on public.app_settings;
create policy settings_admin_select on public.app_settings
for select to authenticated using ((select public.is_encba_admin()));
create policy settings_admin_insert on public.app_settings
for insert to authenticated with check ((select public.is_encba_admin()));
create policy settings_admin_update on public.app_settings
for update to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));
create policy settings_admin_delete on public.app_settings
for delete to authenticated using ((select public.is_encba_admin()));

drop policy if exists event_roster_apply on public.event_roster;
drop policy if exists event_roster_manage on public.event_roster;
drop policy if exists event_roster_read on public.event_roster;
create policy event_roster_select on public.event_roster
for select to authenticated
using (profile_id = (select auth.uid()) or (select public.can_manage_schedule()));
create policy event_roster_insert on public.event_roster
for insert to authenticated
with check (
  (select public.can_manage_schedule())
  or (profile_id = (select auth.uid()) and status = 'applied')
);
create policy event_roster_update on public.event_roster
for update to authenticated
using ((select public.can_manage_schedule()))
with check ((select public.can_manage_schedule()));
create policy event_roster_delete on public.event_roster
for delete to authenticated using ((select public.can_manage_schedule()));

drop policy if exists event_starters_manage on public.event_starters;
create policy event_starters_insert on public.event_starters
for insert to authenticated with check ((select public.can_manage_schedule()));
create policy event_starters_update on public.event_starters
for update to authenticated
using ((select public.can_manage_schedule()))
with check ((select public.can_manage_schedule()));
create policy event_starters_delete on public.event_starters
for delete to authenticated using ((select public.can_manage_schedule()));

drop policy if exists homecoming_campaigns_admin_all on public.homecoming_campaigns;
create policy homecoming_campaigns_admin_insert on public.homecoming_campaigns
for insert to authenticated with check ((select public.is_encba_admin()));
create policy homecoming_campaigns_admin_update on public.homecoming_campaigns
for update to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));
create policy homecoming_campaigns_admin_delete on public.homecoming_campaigns
for delete to authenticated using ((select public.is_encba_admin()));

drop policy if exists homecoming_admin_all on public.homecoming_contacts;
drop policy if exists homecoming_assignee_read on public.homecoming_contacts;
drop policy if exists homecoming_assignee_update on public.homecoming_contacts;
create policy homecoming_select on public.homecoming_contacts
for select to authenticated
using (
  (select public.is_encba_admin())
  or exists (
    select 1 from public.profiles viewer
    where viewer.id = (select auth.uid())
      and (viewer.name = assigned_to_name or viewer.display_name = assigned_to_name)
  )
);
create policy homecoming_admin_insert on public.homecoming_contacts
for insert to authenticated with check ((select public.is_encba_admin()));
create policy homecoming_update on public.homecoming_contacts
for update to authenticated
using (
  (select public.is_encba_admin())
  or exists (
    select 1 from public.profiles viewer
    where viewer.id = (select auth.uid())
      and (viewer.name = assigned_to_name or viewer.display_name = assigned_to_name)
  )
)
with check (
  (select public.is_encba_admin())
  or exists (
    select 1 from public.profiles viewer
    where viewer.id = (select auth.uid())
      and (viewer.name = assigned_to_name or viewer.display_name = assigned_to_name)
  )
);
create policy homecoming_admin_delete on public.homecoming_contacts
for delete to authenticated using ((select public.is_encba_admin()));

-- Public read policies already cover admins. Split ALL policies so SELECT is
-- evaluated exactly once for these reference tables.
drop policy if exists leagues_admin_all on public.leagues;
create policy leagues_admin_insert on public.leagues for insert to authenticated
with check ((select public.is_encba_admin()));
create policy leagues_admin_update on public.leagues for update to authenticated
using ((select public.is_encba_admin())) with check ((select public.is_encba_admin()));
create policy leagues_admin_delete on public.leagues for delete to authenticated
using ((select public.is_encba_admin()));

drop policy if exists places_admin_all on public.places;
create policy places_admin_insert on public.places for insert to authenticated
with check ((select public.is_encba_admin()));
create policy places_admin_update on public.places for update to authenticated
using ((select public.is_encba_admin())) with check ((select public.is_encba_admin()));
create policy places_admin_delete on public.places for delete to authenticated
using ((select public.is_encba_admin()));

drop policy if exists profile_teams_admin_all on public.profile_teams;
create policy profile_teams_admin_insert on public.profile_teams for insert to authenticated
with check ((select public.is_encba_admin()));
create policy profile_teams_admin_update on public.profile_teams for update to authenticated
using ((select public.is_encba_admin())) with check ((select public.is_encba_admin()));
create policy profile_teams_admin_delete on public.profile_teams for delete to authenticated
using ((select public.is_encba_admin()));

drop policy if exists seasons_admin_all on public.seasons;
create policy seasons_admin_insert on public.seasons for insert to authenticated
with check ((select public.is_encba_admin()));
create policy seasons_admin_update on public.seasons for update to authenticated
using ((select public.is_encba_admin())) with check ((select public.is_encba_admin()));
create policy seasons_admin_delete on public.seasons for delete to authenticated
using ((select public.is_encba_admin()));

drop policy if exists operations_admin_all on public.operation_assignments;
create policy operations_admin_insert on public.operation_assignments
for insert to authenticated with check ((select public.is_encba_admin()));
create policy operations_admin_update on public.operation_assignments
for update to authenticated
using ((select public.is_encba_admin())) with check ((select public.is_encba_admin()));
create policy operations_admin_delete on public.operation_assignments
for delete to authenticated using ((select public.is_encba_admin()));

analyze public.events;
analyze public.videos;
analyze public.video_comments;
analyze public.event_roster;
