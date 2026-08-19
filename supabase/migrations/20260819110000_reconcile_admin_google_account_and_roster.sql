begin;

-- 2026 명단표에는 있으나 기존 seed에 빠졌던 두 사람을 가입 자격 명단에 보존한다.
-- 학번·등번호·팀이 원본에 명시되지 않아 임의로 만들지 않고 안전한 기본값만 둔다.
insert into public.member_allowlist (login_name, name, team_codes)
values
  ('김민건', '김민건', array['ENCBA']::text[]),
  ('이호석', '이호석', array['ENCBA']::text[])
on conflict (login_name) do update
set name = excluded.name,
    is_active = true;

-- 최재원의 기존 실명 계정 기록을 새 Google 연결 계정으로 이어 붙인다.
-- 기존 행은 참조 무결성과 감사 이력을 위해 삭제하지 않고 비활성 보관한다.
do $$
declare
  legacy_id uuid := 'ab8773b6-f61c-47e8-923c-abdfb74ecbb1';
  google_id uuid := 'ca71127f-4a64-4d1d-bbab-0d6b830bc2d6';
begin
  if exists (select 1 from public.profiles where id = legacy_id)
     and exists (select 1 from public.profiles where id = google_id) then
    update public.profiles as target
    set avatar_path = coalesce(target.avatar_path, legacy.avatar_path),
        generation = case when target.generation = 1 then legacy.generation else target.generation end
    from public.profiles as legacy
    where target.id = google_id and legacy.id = legacy_id;

    update public.operation_assignments
    set profile_id = google_id
    where profile_id = legacy_id;

    insert into public.profile_teams (profile_id, team_id)
    select google_id, team_id
    from public.profile_teams
    where profile_id = legacy_id
    on conflict do nothing;

    update public.profiles
    set is_active = false,
        is_admin = false,
        is_schedule_manager = false,
        leadership_role = 'member'
    where id = legacy_id;
  end if;
end;
$$;

commit;
