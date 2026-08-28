-- 계정 활성화 요청함 롤백: 함수와 테이블을 모두 내린다.

drop function if exists public.list_account_activation_requests();
drop function if exists public.resolve_account_activation(uuid, boolean);
drop function if exists public.request_account_activation(text);
drop table if exists public.account_activation_requests cascade;
