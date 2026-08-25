-- 오류 제보함 롤백: 테이블과 정책을 모두 내린다.

drop table if exists public.error_reports cascade;
