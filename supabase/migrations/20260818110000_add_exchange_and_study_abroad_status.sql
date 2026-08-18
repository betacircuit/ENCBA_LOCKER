begin;

-- 새 enum 값은 이 트랜잭션 안에서는 쓸 수 없으므로(Postgres 제약),
-- 추가만 하고 이 파일 안에서 바로 사용하지 않는다.
alter type public.membership_status add value if not exists 'exchange_student';
alter type public.membership_status add value if not exists 'study_abroad';

commit;
