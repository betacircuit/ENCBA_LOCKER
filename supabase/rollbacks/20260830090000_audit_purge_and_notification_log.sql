-- 롤백: 정리 작업과 알림 기록을 모두 내린다.

select cron.unschedule('encba-purge-audit-logs-after-six-months')
where exists (
  select 1 from cron.job
  where jobname = 'encba-purge-audit-logs-after-six-months'
);
select cron.unschedule('encba-purge-notification-log')
where exists (
  select 1 from cron.job where jobname = 'encba-purge-notification-log'
);

drop function if exists public.list_my_notifications(timestamptz);
drop function if exists public.list_notification_log(int);
drop function if exists public.notify_comment_targets(uuid, text, text);
drop function if exists public.purge_expired_notification_log();
drop function if exists public.purge_expired_audit_logs();
drop table if exists public.notification_log cascade;
