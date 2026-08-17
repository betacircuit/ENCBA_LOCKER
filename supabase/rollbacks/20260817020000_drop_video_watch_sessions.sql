-- 20260817020000_drop_video_watch_sessions.sql 되돌리기.
-- 초기 스키마의 정의를 그대로 복원한다. 삭제된 시청 기록 자체는 복구되지 않는다.

create table if not exists public.video_watch_sessions (
  id bigint generated always as identity primary key,
  video_id uuid not null references public.videos(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  watched_seconds integer not null default 0 check (watched_seconds >= 0),
  last_position_seconds integer not null default 0 check (last_position_seconds >= 0),
  completed boolean not null default false,
  started_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (video_id, profile_id)
);

create index if not exists video_watch_video_idx
  on public.video_watch_sessions (video_id, watched_seconds desc);

alter table public.video_watch_sessions enable row level security;

create policy video_watch_own_write on public.video_watch_sessions
for insert to authenticated
with check (profile_id = (select auth.uid()));

create policy video_watch_own_update on public.video_watch_sessions
for update to authenticated
using (profile_id = (select auth.uid()))
with check (profile_id = (select auth.uid()));

create policy video_watch_read on public.video_watch_sessions
for select to authenticated
using (
  profile_id = (select auth.uid())
  or (select public.is_encba_admin())
);

grant select on public.video_watch_sessions to authenticated;
grant insert, update, delete on public.video_watch_sessions to authenticated;

create or replace function public.record_video_watch(
  requested_video_id uuid,
  watched_delta_seconds integer,
  requested_position_seconds integer,
  requested_completed boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'ENCBA_AUTH_REQUIRED';
  end if;
  insert into public.video_watch_sessions (
    video_id, profile_id, watched_seconds, last_position_seconds, completed
  ) values (
    requested_video_id,
    auth.uid(),
    least(greatest(watched_delta_seconds, 0), 30),
    greatest(requested_position_seconds, 0),
    requested_completed
  )
  on conflict (video_id, profile_id) do update set
    watched_seconds = public.video_watch_sessions.watched_seconds + excluded.watched_seconds,
    last_position_seconds = excluded.last_position_seconds,
    completed = public.video_watch_sessions.completed or excluded.completed,
    last_seen_at = now();
end;
$$;

revoke all on function public.record_video_watch(uuid, integer, integer, boolean) from public;
grant execute on function public.record_video_watch(uuid, integer, integer, boolean) to authenticated;
