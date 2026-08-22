-- IB 운영 배정 실시간 반영
--
-- 관리자가 학기 초 IB 운영표를 올리면 배정받은 부원의 앱이 재접속 없이
-- 홈·일정·운영 화면에 새 배정을 바로 보여야 한다. 앱이
-- operation_assignments 테이블의 INSERT/UPDATE를 구독하므로 이 테이블을
-- supabase_realtime 발행물에 추가한다.
--
-- UPDATE 페이로드에 변경된 행 전체가 담기도록 replica identity를 full로
-- 맞춘다(기본값 default는 기본키만 담아 앱 필터 assignee_id 비교에 불편).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'operation_assignments'
  ) then
    alter table public.operation_assignments replica identity full;
    alter publication supabase_realtime add table public.operation_assignments;
  end if;
end
$$;