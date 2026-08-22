begin;

-- 제목만으로도 공지를 올릴 수 있어야 한다. body는 여전히 not null이지만
-- 빈 문자열을 허용한다.
alter table public.announcements
  drop constraint if exists announcements_body_check;
alter table public.announcements
  add constraint announcements_body_check
  check (char_length(body) between 0 and 10000);

commit;
