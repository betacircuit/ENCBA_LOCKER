begin;

-- 지금까지 공지 투표는 항목(poll_options)만 있고 "무엇을 묻는 투표인지"는
-- 공지 제목/본문에 얹어 써야 했다(예: 제목 "회식 안내"인데 실제 투표
-- 질문은 "메뉴를 골라주세요"). 투표 전용 질문 문구를 공지 제목과 분리해
-- 따로 저장한다. 이미 저장된 공지는 빈 문자열이 기본값이라 예전 투표
-- UI도 그대로 동작한다.
alter table public.announcements
  add column if not exists poll_question text not null default '';

alter table public.announcements
  drop constraint if exists announcements_poll_question_check,
  add constraint announcements_poll_question_check
  check (char_length(poll_question) <= 200);

notify pgrst, 'reload schema';

commit;
