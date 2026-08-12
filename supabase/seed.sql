-- 실명 회원가입 허용 명단. 비밀번호는 이 테이블이 아니라 Supabase Auth에 해시로 저장됩니다.
insert into public.member_allowlist (
  login_name, name, student_year, membership_status,
  is_admin, is_schedule_manager, team_codes
)
values
  ('최재원', '최재원', null, 'yb', true, true, array['ENCBA']),
  ('강준성', '강준성', null, 'yb', false, false, array['ENCBA']),
  ('김연준', '김연준', null, 'yb', false, false, array['ENCBA']),
  ('김정우', '김정우', null, 'yb', false, false, array['ENCBA']),
  ('김지원', '김지원', null, 'yb', false, false, array['ENCBA']),
  ('민영웅', '민영웅', null, 'yb', false, false, array['ENCBA']),
  ('박조한', '박조한', null, 'yb', false, false, array['ENCBA']),
  ('서정우', '서정우', null, 'yb', false, false, array['ENCBA']),
  ('용승현', '용승현', null, 'yb', false, false, array['ENCBA']),
  ('유원경', '유원경', null, 'yb', false, false, array['ENCBA']),
  ('이민섭', '이민섭', null, 'yb', false, false, array['ENCBA']),
  ('이시원', '이시원', null, 'yb', false, false, array['ENCBA']),
  ('이우진', '이우진', null, 'yb', false, false, array['ENCBA']),
  ('이준상', '이준상', null, 'yb', false, false, array['ENCBA']),
  ('전현우', '전현우', null, 'yb', false, false, array['ENCBA']),
  ('정승환', '정승환', null, 'yb', false, false, array['ENCBA']),
  ('임준호', '임준호', null, 'yb', false, false, array['ENCBA']),
  ('최정우', '최정우', null, 'yb', false, false, array['ENCBA']),
  ('홍성준', '홍성준', null, 'yb', false, false, array['ENCBA']),
  ('김건오', '김건오', null, 'yb', false, false, array['ENCBA']),
  ('김창래', '김창래', null, 'yb', false, false, array['ENCBA']),
  ('나윤석', '나윤석', null, 'yb', false, false, array['ENCBA']),
  ('박서연', '박서연', null, 'yb', false, false, array['ENCBA']),
  ('유승준', '유승준', null, 'yb', false, false, array['ENCBA']),
  ('유준열', '유준열', null, 'yb', false, false, array['ENCBA']),
  ('이승민', '이승민', null, 'yb', false, false, array['ENCBA']),
  ('이준성', '이준성', null, 'yb', false, false, array['ENCBA']),
  ('이현우', '이현우', null, 'yb', false, false, array['ENCBA']),
  ('정민혁', '정민혁', null, 'yb', false, false, array['ENCBA']),
  ('정유석', '정유석', null, 'yb', false, false, array['ENCBA']),
  ('조서현', '조서현', null, 'yb', false, false, array['ENCBA']),
  ('하승윤', '하승윤', null, 'yb', false, false, array['ENCBA']),
  ('시유상', '시유상', 22, 'military_leave', false, false, array['ENCBA']),
  ('이영서', '이영서', 23, 'military_leave', false, false, array['ENCBA']),
  ('김창용', '김창용', 23, 'military_leave', false, false, array['ENCBA']),
  ('방준모', '방준모', 24, 'military_leave', false, false, array['ENCBA']),
  ('황재문', '황재문', 24, 'military_leave', false, false, array['ENCBA']),
  ('유시현', '유시현', 24, 'military_leave', false, false, array['ENCBA']),
  ('김재룡', '김재룡', 24, 'military_leave', false, false, array['ENCBA'])
on conflict (login_name) do update set
  name = excluded.name,
  student_year = excluded.student_year,
  membership_status = excluded.membership_status,
  is_admin = excluded.is_admin,
  is_schedule_manager = excluded.is_schedule_manager,
  team_codes = excluded.team_codes;

update public.member_allowlist
set leadership_role = case name
  when '최재원' then 'admin'
  when '임준호' then 'captain'
  when '홍성준' then 'manager'
  else leadership_role
end,
is_admin = name = '최재원',
is_schedule_manager = case when name = '임준호' then true else is_schedule_manager end
where name in ('최재원', '임준호', '홍성준');

insert into public.app_settings (key, value)
values ('ib_team_divisions', '{"ENCBA": 2, "BEN": 2, "신입생": 2}'::jsonb)
on conflict (key) do update set value = excluded.value;
