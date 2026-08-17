begin;

-- 시청 현황 기능을 제거한다.
-- 복기 화면은 재생 위치를 실시간으로만 사용하고 서버에 남기지 않는다.
-- 정책·인덱스·권한은 테이블과 함께 사라지므로 별도로 지우지 않는다.

drop function if exists public.record_video_watch(uuid, integer, integer, boolean);
drop table if exists public.video_watch_sessions;

commit;
