begin;

alter table public.announcements
  drop constraint if exists announcements_poll_question_check;

alter table public.announcements
  drop column if exists poll_question;

notify pgrst, 'reload schema';

commit;
