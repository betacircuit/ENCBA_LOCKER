-- 오류 제보함
--
-- 부원이 오류 제보 화면에서 쓴 내용을 메일이 아니라 DB에 남긴다.
-- 작성자·학번·계정·실행 환경은 앱이 자동으로 채워 넣고, 제보는
-- 관리자만 볼 수 있다. 관리자는 읽음 표시를 하거나 삭제로 처리한다.

create table if not exists public.error_reports (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  student_id text,
  email text,
  environment text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.error_reports enable row level security;

drop policy if exists error_reports_insert_own on public.error_reports;
create policy error_reports_insert_own on public.error_reports
  for insert to authenticated with check (profile_id = auth.uid());

drop policy if exists error_reports_read_admin on public.error_reports;
create policy error_reports_read_admin on public.error_reports
  for select to authenticated using (public.is_encba_admin());

drop policy if exists error_reports_update_admin on public.error_reports;
create policy error_reports_update_admin on public.error_reports
  for update to authenticated
  using (public.is_encba_admin())
  with check (public.is_encba_admin());

drop policy if exists error_reports_delete_admin on public.error_reports;
create policy error_reports_delete_admin on public.error_reports
  for delete to authenticated using (public.is_encba_admin());

create index if not exists error_reports_created_at_idx
  on public.error_reports (created_at desc);
