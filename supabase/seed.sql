-- 로컬 개발 및 초기 운영용 허용 명단입니다.
insert into public.member_allowlist (
  email, name, student_year, generation, team_codes
)
values
  ('admin@encba.kr', '이준호', 21, 40, array['ENCBA']),
  ('member@encba.kr', '김민수', 22, 41, array['ENCBA', 'BEN'])
on conflict (email) do update set
  name = excluded.name,
  student_year = excluded.student_year,
  generation = excluded.generation,
  team_codes = excluded.team_codes;

-- 두 계정이 앱에서 가입한 뒤 아래 문장으로 최초 관리자를 승격합니다.
-- service_role 키를 앱에 넣지 말고 Supabase SQL Editor에서만 실행하세요.
update public.profiles
set is_admin = true
where email = 'admin@encba.kr';
