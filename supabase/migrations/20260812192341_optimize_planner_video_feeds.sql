begin;

-- Planner uses a stable starts_at/id keyset and only reads active events.
-- This replaces the older starts_at/kind index, whose second column did not
-- match the feed order and duplicated the same leading key.
create index if not exists events_upcoming_starts_idx
  on public.events (starts_at, id)
  where cancelled_at is null;

drop index if exists public.events_upcoming_idx;

-- The video home feed is global and ordered by recency, not category first.
create index if not exists videos_recent_idx
  on public.videos (created_at desc, id);

commit;
