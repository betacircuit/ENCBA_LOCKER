-- 관리자 판정 불일치 수정
--
-- leadership_role='admin'으로 지정됐지만 profiles.is_admin 플래그가 꺼져
-- 있는 계정이 있었다. 앱은 leadership_role 기준으로 "관리자" 뱃지를
-- 보여주므로 본인은 관리자라고 생각하지만, is_encba_admin()은
-- is_admin 또는 주장만 통과시켜 멤버 정보·직책 수정이 전부 거절됐다.
--
-- 이제 leadership_role이 'admin'이거나 'captain'이면(활성 계정)
-- is_encba_admin()이 true를 돌려준다.

create or replace function public.is_encba_admin()
returns boolean
language sql
stable
as $$
  select coalesce(
    (
      select p.is_active
        and (p.is_admin or p.leadership_role in ('admin', 'captain'))
      from public.profiles p
      where p.id = (select auth.uid())
    ),
    false
  );
$$;

revoke all on function public.is_encba_admin() from public, anon;
grant execute on function public.is_encba_admin() to authenticated;