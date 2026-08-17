begin;

-- 운영진의 INSERT ... RETURNING은 새 행을 같은 문장에서 다시 조회한다.
-- can_access_event()의 테이블 재조회만 사용하면 새 행이 아직 보이지 않아
-- 정상 INSERT가 RLS 오류로 보고될 수 있으므로 운영 권한을 먼저 허용한다.
drop policy if exists events_read on public.events;
create policy events_read on public.events
for select to authenticated
using (
  (select public.can_manage_schedule())
  or (select public.can_access_event(id))
);

-- (event_id, choice, responded_at) 인덱스가 같은 선두 키를 포함하므로
-- 중복 인덱스를 제거해 참석 응답 쓰기 비용과 저장 공간을 줄인다.
drop index if exists public.attendance_event_choice_idx;

-- FOR ALL 관리 정책이 읽기 정책과 중복 평가되던 것을 명령별로 분리한다.
drop policy if exists announcement_event_links_read
  on public.announcement_event_links;
drop policy if exists announcement_event_links_manage
  on public.announcement_event_links;

create policy announcement_event_links_read
on public.announcement_event_links
for select to authenticated
using (
  (select public.is_encba_admin())
  or (select public.can_access_event(event_id))
);

create policy announcement_event_links_insert
on public.announcement_event_links
for insert to authenticated
with check ((select public.is_encba_admin()));

create policy announcement_event_links_update
on public.announcement_event_links
for update to authenticated
using ((select public.is_encba_admin()))
with check ((select public.is_encba_admin()));

create policy announcement_event_links_delete
on public.announcement_event_links
for delete to authenticated
using ((select public.is_encba_admin()));

commit;
