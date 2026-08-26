begin;

-- Expand the existing soft-cancellation contract. Older clients continue to
-- hide rows with cancelled_at while newer clients can explain the cancellation.
alter table public.events
  add column if not exists cancellation_reason text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'events_cancellation_reason_length_check'
      and conrelid = 'public.events'::regclass
  ) then
    alter table public.events
      add constraint events_cancellation_reason_length_check
      check (
        cancellation_reason is null
        or char_length(btrim(cancellation_reason)) between 1 and 500
      );
  end if;
end
$$;

grant update (cancellation_reason) on public.events to authenticated;

-- Cancelled events are intentionally included in the new planner query.
create index if not exists events_planner_starts_idx
  on public.events (starts_at, id);

drop trigger if exists events_set_updated_at on public.events;
create trigger events_set_updated_at before update of
  title, kind, starts_at, ends_at, season_id, league_id, place_id,
  place_label, court, target_team, opponent, opponents, uniform_colors, memo,
  capacity, ob_participant_count, response_enabled, response_deadline,
  recurrence_rule, poll_options, visibility, parent_event_id, map_reference,
  updated_by, cancelled_at, cancellation_reason
on public.events for each row execute function public.set_updated_at();

drop trigger if exists events_audit on public.events;
create trigger events_audit after insert or delete or update of
  title, kind, starts_at, ends_at, place_id, place_label, court, target_team,
  opponent, opponents, uniform_colors, memo, capacity, ob_participant_count,
  response_enabled, response_deadline, recurrence_rule, poll_options,
  visibility, map_reference, cancelled_at, cancellation_reason
on public.events
for each row execute function public.write_audit_log();

notify pgrst, 'reload schema';

commit;
