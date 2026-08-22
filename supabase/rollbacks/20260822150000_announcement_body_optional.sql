begin;

alter table public.announcements
  drop constraint if exists announcements_body_check;
alter table public.announcements
  add constraint announcements_body_check
  check (char_length(body) between 1 and 10000);

commit;
