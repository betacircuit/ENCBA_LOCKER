-- 앱 수요조사
--
-- 홈 화면의 별 버튼으로 "앱 출시 수요"를 표시한다. 부원은 자기 별 하나만
-- 누를 수 있고(토글), 목록은 관리자만 읽을 수 있다. 관리자는 개수만 세서
-- 홈 화면 배지로 보여 준다.

create table if not exists public.app_demand_votes (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.app_demand_votes enable row level security;

drop policy if exists app_demand_insert_own on public.app_demand_votes;
create policy app_demand_insert_own on public.app_demand_votes
  for insert to authenticated with check (profile_id = auth.uid());

drop policy if exists app_demand_delete_own on public.app_demand_votes;
create policy app_demand_delete_own on public.app_demand_votes
  for delete to authenticated using (profile_id = auth.uid());

drop policy if exists app_demand_read_own on public.app_demand_votes;
create policy app_demand_read_own on public.app_demand_votes
  for select to authenticated using (profile_id = auth.uid());

drop policy if exists app_demand_read_admin on public.app_demand_votes;
create policy app_demand_read_admin on public.app_demand_votes
  for select to authenticated using (public.is_encba_admin());
