-- 영상 별점
--
-- 부원이 복기·하이라이트 영상에 1~5점 별점을 매긴다. 좋아요와 달리
-- 평균 점수를 집계해 영상 품질 피드백으로 쓴다. 한 사람당 영상 하나에
-- 한 번만 평가할 수 있고 다시 누르면 덮어쓴다.

create table if not exists public.video_ratings (
  video_id uuid not null references public.videos(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  stars smallint not null check (stars between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (video_id, profile_id)
);

alter table public.video_ratings enable row level security;

drop policy if exists video_ratings_read on public.video_ratings;
create policy video_ratings_read on public.video_ratings
  for select to authenticated using (true);

drop policy if exists video_ratings_write_own on public.video_ratings;
create policy video_ratings_write_own on public.video_ratings
  for insert to authenticated with check (profile_id = auth.uid());

drop policy if exists video_ratings_update_own on public.video_ratings;
create policy video_ratings_update_own on public.video_ratings
  for update to authenticated using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

create trigger video_ratings_set_updated_at before update on public.video_ratings
  for each row execute function public.set_updated_at();

-- 감사 로그는 개인 취향 기록이라 남기지 않는다.