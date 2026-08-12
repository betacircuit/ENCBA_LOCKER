begin;

-- IB is available during the current break. Semester locking can be restored
-- later with an explicit app setting instead of a hard-coded date trigger.
drop trigger if exists events_enforce_ib_semester on public.events;

alter table public.events
  add column if not exists opponents text[] not null default '{}'::text[];

update public.events
set opponents = array[btrim(opponent)]
where cardinality(opponents) = 0
  and nullif(btrim(opponent), '') is not null;

do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select conname
    from pg_constraint
    where conrelid = 'public.events'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%kind%training%poll_options%'
  loop
    execute format('alter table public.events drop constraint %I', constraint_name);
  end loop;
end $$;

alter table public.events
  drop constraint if exists events_opponents_count_check,
  add constraint events_opponents_count_check check (
    cardinality(opponents) <= 2
    and array_position(opponents, '') is null
  ),
  drop constraint if exists events_match_opponents_check,
  add constraint events_match_opponents_check check (
    (kind = 'scrimmage' and cardinality(opponents) = 1)
    or (kind = 'three_way' and cardinality(opponents) = 2)
    or kind not in ('scrimmage', 'three_way')
  ) not valid;

create index if not exists events_upcoming_starts_idx
  on public.events (starts_at, id)
  where cancelled_at is null;

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
  response_deadline, recurrence_rule, poll_options, visibility, cancelled_at
on public.events
for each row execute function public.write_audit_log();

create or replace function public.can_manage_schedule()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select public.is_encba_admin());
$$;

revoke all on function public.can_manage_schedule() from public;
grant execute on function public.can_manage_schedule() to authenticated;

create or replace function public.is_encba_manager()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select p.leadership_role = 'manager' and p.is_active
      from public.profiles p
      where p.id = (select auth.uid())
    ),
    false
  );
$$;

revoke all on function public.is_encba_manager() from public;
grant execute on function public.is_encba_manager() to authenticated;

drop policy if exists videos_insert on public.videos;
create policy videos_insert on public.videos for insert to authenticated
with check (
  uploaded_by = (select auth.uid())
  and (
    category in ('review', 'shared')
    or (category = 'highlight' and (select public.is_encba_manager()))
  )
);

drop policy if exists videos_update on public.videos;
create policy videos_update on public.videos for update to authenticated
using (
  category in ('review', 'shared')
  or (
    category = 'highlight'
    and ((select public.is_encba_manager()) or (select public.is_encba_admin()))
  )
)
with check (
  category in ('review', 'shared')
  or (
    category = 'highlight'
    and ((select public.is_encba_manager()) or (select public.is_encba_admin()))
  )
);

drop policy if exists videos_delete on public.videos;
create policy videos_delete on public.videos for delete to authenticated
using (
  category in ('review', 'shared')
  or (
    category = 'highlight'
    and ((select public.is_encba_manager()) or (select public.is_encba_admin()))
  )
);

revoke update on public.events from authenticated;
grant update (
  title, kind, starts_at, ends_at, season_id, league_id, place_id, place_label,
  court, target_team, opponent, opponents, uniform_colors, memo, capacity,
  response_enabled, response_deadline, recurrence_rule, poll_options,
  visibility, parent_event_id, updated_by, cancelled_at, attending_count
) on public.events to authenticated;

with admin_profile as (
  select id
  from public.profiles
  where is_admin or leadership_role = 'captain'
  order by is_admin desc, created_at
  limit 1
), kst_today as (
  select (timezone('Asia/Seoul', now()))::date as day
), sample_events (
  title, kind, day_offset, starts_at, ends_at, place_label, court,
  uniform_colors, opponents, memo, capacity
) as (
  values
    ('정기 훈련', 'training', 1, time '18:00', time '20:00',
      '71동 종합체육관', 'A코트', '{}'::text[], '{}'::text[],
      '10분 전까지 모여 스트레칭을 시작합니다.', 24::smallint),
    ('아농', 'morning', 2, time '08:00', time '10:00',
      '71-1동 신체육관', null, '{}'::text[], '{}'::text[],
      '8명 이상 모이면 진행합니다.', 16::smallint),
    ('IB 1부', 'ib_division_1', 3, time '20:00', time '21:00',
      '71동 종합체육관', 'B코트', array['검']::text[], '{}'::text[],
      '경기 시작 40분 전 집합합니다.', null::smallint),
    ('IB 2부', 'ib_division_2', 5, time '19:00', time '20:00',
      '71동 종합체육관', 'A코트', array['흰']::text[], '{}'::text[],
      '경기 시작 30분 전 집합합니다.', null::smallint),
    ('연습 경기', 'scrimmage', 7, time '18:30', time '20:30',
      '900동 기숙사체육관', null, array['검', '흰']::text[], array['스티즈']::text[],
      '경기 시작 30분 전까지 도착해 주세요.', null::smallint),
    ('삼파전', 'three_way', 10, time '14:00', time '18:00',
      '71동 종합체육관', '전체', array['검', '흰']::text[], array['농구부', '그래비티']::text[],
      '세 팀이 순환 경기로 진행합니다.', null::smallint)
)
insert into public.events (
  title, kind, starts_at, ends_at, place_label, court, target_team,
  uniform_colors, opponents, memo, capacity, response_enabled,
  response_deadline, poll_options, visibility, created_by, updated_by
)
select
  sample.title,
  sample.kind,
  (calendar.day + sample.day_offset + sample.starts_at) at time zone 'Asia/Seoul',
  (calendar.day + sample.day_offset + sample.ends_at) at time zone 'Asia/Seoul',
  sample.place_label,
  sample.court,
  '전체',
  sample.uniform_colors,
  sample.opponents,
  sample.memo,
  sample.capacity,
  true,
  ((calendar.day + sample.day_offset + sample.starts_at) at time zone 'Asia/Seoul')
    - case when sample.kind in (
        'internal', 'pickup', 'ib_division_1', 'ib_division_2',
        'ib_freshman', 'scrimmage', 'three_way', 'external'
      ) then interval '3 hours' else interval '1 hour' end,
  '["참석", "불참", "미정"]'::jsonb,
  'team',
  admin_profile.id,
  admin_profile.id
from sample_events sample
cross join admin_profile
cross join kst_today calendar
where not exists (
  select 1
  from public.events existing
  where existing.title = sample.title
    and existing.starts_at =
      (calendar.day + sample.day_offset + sample.starts_at) at time zone 'Asia/Seoul'
);

notify pgrst, 'reload schema';

commit;
