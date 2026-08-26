begin;

drop trigger if exists events_set_updated_at on public.events;
create trigger events_set_updated_at before update of
  title, kind, starts_at, ends_at, season_id, league_id, place_id,
  place_label, court, target_team, opponent, opponents, uniform_colors, memo,
  capacity, response_enabled, response_deadline, recurrence_rule,
  poll_options, visibility, parent_event_id, updated_by, cancelled_at
on public.events for each row execute function public.set_updated_at();

drop trigger if exists events_audit on public.events;
create trigger events_audit after insert or delete or update of
  title, kind, starts_at, ends_at, place_id, place_label, court, target_team,
  opponent, opponents, uniform_colors, memo, capacity, response_enabled,
  response_deadline, recurrence_rule, poll_options, visibility, map_reference,
  cancelled_at
on public.events
for each row execute function public.write_audit_log();

drop index if exists public.events_planner_starts_idx;
alter table public.events
  drop constraint if exists events_cancellation_reason_length_check;
alter table public.events
  drop column if exists cancellation_reason;

notify pgrst, 'reload schema';

commit;
