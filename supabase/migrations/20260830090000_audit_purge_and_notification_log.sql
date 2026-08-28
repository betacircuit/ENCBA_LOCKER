-- 수정 이력 자동 정리 · 서버 알림 기록 · 언급 알림
--
-- 1) audit_logs는 앱을 쓸수록 무한히 쌓인다. 일정과 같은 규칙(6개월)으로
--    매일 정리해 무료 플랜의 500MB를 갉아먹지 않게 한다.
-- 2) 알림 기록이 지금은 기기 안에만 남아서, 관리자가 "그 알림이 실제로
--    나갔는지"를 확인할 방법이 없었다. 보낸 알림을 서버에도 남긴다.
-- 3) 복기 댓글에서 누군가를 지목하면 그 사람에게 알림이 가야 한다.

begin;

-- 1) 수정 이력 6개월 정리 ------------------------------------------------

create or replace function public.purge_expired_audit_logs()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_count integer;
begin
  delete from public.audit_logs
  where created_at < now() - interval '6 months';
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function public.purge_expired_audit_logs() from public;

-- 일정 정리(03:17)와 시간을 벌려 두 작업이 겹치지 않게 한다.
select cron.unschedule('encba-purge-audit-logs-after-six-months')
where exists (
  select 1 from cron.job
  where jobname = 'encba-purge-audit-logs-after-six-months'
);

select cron.schedule(
  'encba-purge-audit-logs-after-six-months',
  '42 3 * * *',
  $$select public.purge_expired_audit_logs();$$
);

-- 2) 서버 알림 기록 --------------------------------------------------------

create table if not exists public.notification_log (
  id uuid primary key default gen_random_uuid(),
  -- 받는 사람. 전체 공지처럼 대상이 넓으면 null이다.
  profile_id uuid references public.profiles(id) on delete cascade,
  category text not null default 'announcements'
    check (category in ('announcements', 'events', 'videos')),
  title text not null,
  body text not null default '',
  -- 눌렀을 때 열 앱 내 주소.
  route text,
  created_at timestamptz not null default now()
);

create index if not exists notification_log_created_at_idx
  on public.notification_log (created_at desc);
create index if not exists notification_log_profile_idx
  on public.notification_log (profile_id, created_at desc);

alter table public.notification_log enable row level security;

-- 자기에게 온 알림은 본인이, 전체 기록은 관리자만 본다.
drop policy if exists notification_log_read on public.notification_log;
create policy notification_log_read on public.notification_log
  for select to authenticated
  using (profile_id = (select auth.uid()) or public.is_encba_admin());

-- 쓰기는 security definer 함수로만 한다. 직접 insert 정책은 두지 않는다.

-- 기록도 6개월만 보관한다. 알림은 지나면 다시 볼 일이 거의 없다.
create or replace function public.purge_expired_notification_log()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_count integer;
begin
  delete from public.notification_log
  where created_at < now() - interval '6 months';
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function public.purge_expired_notification_log() from public;

select cron.unschedule('encba-purge-notification-log')
where exists (
  select 1 from cron.job where jobname = 'encba-purge-notification-log'
);

select cron.schedule(
  'encba-purge-notification-log',
  '52 3 * * *',
  $$select public.purge_expired_notification_log();$$
);

-- 관리자가 전체 알림 기록을 읽는다. 받는 사람 이름을 함께 붙여 준다.
create or replace function public.list_notification_log(
  requested_limit int default 200
)
returns table (
  id uuid,
  profile_id uuid,
  recipient_name text,
  category text,
  title text,
  body text,
  route text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select n.id, n.profile_id,
         coalesce(nullif(p.display_name, ''), p.name, '전체') as recipient_name,
         n.category, n.title, n.body, n.route, n.created_at
  from public.notification_log n
  left join public.profiles p on p.id = n.profile_id
  where public.is_encba_admin()
  order by n.created_at desc
  limit least(greatest(requested_limit, 1), 500);
$$;

revoke all on function public.list_notification_log(int) from public;
grant execute on function public.list_notification_log(int) to authenticated;

-- 3) 언급·피드백 알림 -------------------------------------------------------

-- 복기 댓글에서 지목한 사람에게 알림을 남긴다. 지목 대상은 명단
-- (member_allowlist) 기준이라 가입한 사람만 실제로 받는다.
--
-- 호출자가 그 영상에 댓글을 쓸 수 있는지는 RLS가 이미 판정하므로, 여기서는
-- 자기 자신에게 보내지 않는 것만 걸러 준다.
create or replace function public.notify_comment_targets(
  requested_comment uuid,
  requested_video_title text,
  requested_route text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  actor_name text;
  inserted_count integer := 0;
begin
  if actor is null then
    raise exception 'ENCBA_LOGIN_REQUIRED';
  end if;

  select coalesce(nullif(display_name, ''), name, '부원')
  into actor_name
  from public.profiles
  where id = actor;

  with targets as (
    select distinct a.consumed_by as profile_id
    from public.video_comment_targets t
    join public.member_allowlist a on a.id = t.member_allowlist_id
    where t.comment_id = requested_comment
      and a.consumed_by is not null
      and a.consumed_by <> actor
  )
  insert into public.notification_log (profile_id, category, title, body, route)
  select
    targets.profile_id,
    'videos',
    coalesce(actor_name, '부원') || '님이 회원님을 언급했습니다',
    case
      when coalesce(requested_video_title, '') = '' then '복기 영상에 피드백이 달렸어요.'
      else requested_video_title || ' 복기에 피드백이 달렸어요.'
    end,
    requested_route
  from targets;

  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

revoke all on function public.notify_comment_targets(uuid, text, text) from public;
grant execute on function public.notify_comment_targets(uuid, text, text)
  to authenticated;

-- 부원이 자기에게 온 알림을 읽는다. 앱은 마지막으로 확인한 시각 이후 것만
-- 가져와 기기 기록에 합친다.
create or replace function public.list_my_notifications(
  requested_since timestamptz default null
)
returns table (
  id uuid,
  category text,
  title text,
  body text,
  route text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select n.id, n.category, n.title, n.body, n.route, n.created_at
  from public.notification_log n
  where n.profile_id = (select auth.uid())
    and (requested_since is null or n.created_at > requested_since)
  order by n.created_at desc
  limit 100;
$$;

revoke all on function public.list_my_notifications(timestamptz) from public;
grant execute on function public.list_my_notifications(timestamptz)
  to authenticated;

-- 새 알림이 도착하면 앱이 재접속 없이 받는다.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notification_log'
  ) then
    alter publication supabase_realtime add table public.notification_log;
  end if;
end
$$;

notify pgrst, 'reload schema';

commit;
