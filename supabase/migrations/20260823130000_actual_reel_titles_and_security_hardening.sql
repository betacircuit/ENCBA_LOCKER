begin;

set local statement_timeout = '10s';

update public.videos as video
set title = reel.title
from (
  values
    ('Kusf 하이라이트🏀 진격의 엔크바🦾🦾', 'https://www.instagram.com/reel/Db2nVhDz4Fq/'),
    ('엔크바 1학기 외부대회 하이라이트🏀', 'https://www.instagram.com/reel/DajgzpRTc4e/'),
    ('살짝 꼬니까 다 들어가네?🤞', 'https://www.instagram.com/reel/DZDMprWogCr/'),
    ('서울대 대표 농친자들, 엔크바의 귀염뽀짝한 24시간🏀', 'https://www.instagram.com/reel/DXPE0fsEwcm/'),
    ('2025 The Process 엔크바 하이라이트🔥', 'https://www.instagram.com/reel/DTnGCB7E50t/')
) as reel(title, url)
where video.source_type = 'instagram'
  and video.source_url = reel.url
  and video.title ~ '^ENCBA REEL [1-5]$';

create or replace function public.seed_default_highlights_for_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (new.is_admin or new.leadership_role = 'captain') then
    return new;
  end if;

  insert into public.videos (
    title, category, source_url, youtube_id, source_type, uploaded_by
  )
  select reel.title, 'highlight'::public.video_category, reel.url, null, 'instagram', new.id
  from (
    values
      ('Kusf 하이라이트🏀 진격의 엔크바🦾🦾', 'https://www.instagram.com/reel/Db2nVhDz4Fq/'),
      ('엔크바 1학기 외부대회 하이라이트🏀', 'https://www.instagram.com/reel/DajgzpRTc4e/'),
      ('살짝 꼬니까 다 들어가네?🤞', 'https://www.instagram.com/reel/DZDMprWogCr/'),
      ('서울대 대표 농친자들, 엔크바의 귀염뽀짝한 24시간🏀', 'https://www.instagram.com/reel/DXPE0fsEwcm/'),
      ('2025 The Process 엔크바 하이라이트🔥', 'https://www.instagram.com/reel/DTnGCB7E50t/')
  ) as reel(title, url)
  where not exists (
    select 1 from public.videos existing where existing.source_url = reel.url
  );

  return new;
end;
$$;

-- Trigger functions do not need client EXECUTE privileges.
revoke all on function public.seed_default_highlights_for_admin()
from public, anon, authenticated;

-- This function is called by pg_cron as its owner. Client access would allow
-- arbitrary users to delete every event older than six months.
revoke all on function public.purge_expired_events()
from public, anon, authenticated;

alter table public.events validate constraint events_match_opponents_check;

notify pgrst, 'reload schema';

commit;
