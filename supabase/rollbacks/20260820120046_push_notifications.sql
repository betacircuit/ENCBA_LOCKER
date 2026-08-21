begin;

revoke select, insert, delete
  on table public.push_deliveries from service_role;
revoke usage on sequence public.push_deliveries_id_seq from service_role;

revoke select, update
  on table public.push_subscriptions from service_role;
revoke select, insert, update, delete
  on table public.push_subscriptions from authenticated;
revoke usage on sequence public.push_subscriptions_id_seq from authenticated;

drop policy if exists push_subscriptions_delete_own
  on public.push_subscriptions;
drop policy if exists push_subscriptions_update_own
  on public.push_subscriptions;
drop policy if exists push_subscriptions_insert_own
  on public.push_subscriptions;
drop policy if exists push_subscriptions_select_own
  on public.push_subscriptions;

drop trigger if exists push_subscriptions_set_updated_at
  on public.push_subscriptions;

drop table if exists public.push_deliveries;
drop table if exists public.push_subscriptions;

revoke insert (is_urgent) on public.announcements from authenticated;
revoke update (is_urgent) on public.announcements from authenticated;

alter table public.announcements
  drop column if exists is_urgent;

commit;
