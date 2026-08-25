-- IB 전체 운영 일정 열람
--
-- IB 운영 일정 화면의 "전체 운영 일정" 섹션을 부원 모두가 볼 수 있게 한다.
-- 기존 정책(operations_read_own_or_admin)은 자기 배정·관리자만 허용했으므로
-- authenticated SELECT 전체 허용 정책을 추가한다. 수정(insert/update/delete)
-- 은 기존 관리자 전용 정책을 그대로 따른다.

drop policy if exists operations_read_all on public.operation_assignments;
create policy operations_read_all on public.operation_assignments
  for select to authenticated using (true);
