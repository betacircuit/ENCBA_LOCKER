begin;

-- leadership_role은 관리자/주장/매니저 권한과 직결된 컬럼이라 한 사람당 값 하나만
-- 가진다. 부서장·팀 내 직책처럼 권한과 무관하게 여러 개를 동시에 달 수 있는
-- 표시용 타이틀은 별도 배열 컬럼으로 둔다.
alter table public.member_allowlist
  add column if not exists titles text[] not null default '{}'::text[];
alter table public.profiles
  add column if not exists titles text[] not null default '{}'::text[];

create or replace function public.sync_reservation_role_on_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles as profile
  set is_reservation_manager = allowed.is_reservation_manager,
      department = allowed.department,
      is_freshman = allowed.is_freshman,
      titles = allowed.titles
  from public.member_allowlist as allowed
  where profile.id = new.id
    and allowed.consumed_by = new.id;
  return new;
end;
$$;

drop function if exists public.list_member_directory(text, text);
create function public.list_member_directory(
  requested_status text default 'all',
  requested_query text default ''
)
returns table (
  directory_id text,
  name text,
  student_year smallint,
  generation smallint,
  joined_year smallint,
  membership_status public.membership_status,
  is_active boolean,
  phone text,
  "position" text,
  jersey_number smallint,
  team_codes text[],
  leadership_role text,
  is_reservation_manager boolean,
  department text,
  is_freshman boolean,
  titles text[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(profile.id::text, 'allowlist:' || allowed.id::text),
    coalesce(profile.display_name, allowed.name),
    coalesce(profile.student_year, allowed.student_year),
    coalesce(profile.generation, allowed.generation, 1::smallint),
    coalesce(profile.joined_year, allowed.joined_year),
    coalesce(profile.membership_status, allowed.membership_status),
    coalesce(profile.is_active, allowed.is_active),
    coalesce(nullif(profile.phone, ''), allowed.phone, ''),
    coalesce(profile.position, allowed.position, '미정'),
    coalesce(profile.jersey_number, allowed.jersey_number, 0::smallint),
    case
      when profile.id is null then coalesce(allowed.team_codes, array['ENCBA']::text[])
      else array(
        select team.code
        from public.profile_teams as membership
        join public.teams as team on team.id = membership.team_id
        where membership.profile_id = profile.id
        order by team.code
      )
    end,
    coalesce(profile.leadership_role, allowed.leadership_role, 'member'),
    coalesce(profile.is_reservation_manager, allowed.is_reservation_manager, false),
    coalesce(nullif(profile.department, ''), allowed.department, ''),
    coalesce(profile.is_freshman, allowed.is_freshman, false),
    coalesce(nullif(profile.titles, '{}'::text[]), allowed.titles, '{}'::text[])
  from public.member_allowlist as allowed
  left join public.profiles as profile on profile.id = allowed.consumed_by
  where (select auth.uid()) is not null
    and (
      requested_status = 'all'
      or (requested_status = 'military'
          and coalesce(profile.membership_status, allowed.membership_status) = 'military_leave')
    )
    and (
      nullif(btrim(requested_query), '') is null
      or coalesce(profile.display_name, allowed.name) ilike '%' || btrim(requested_query) || '%'
      or lpad(coalesce(profile.student_year, allowed.student_year, 0)::text, 2, '0')
        = regexp_replace(requested_query, '[^0-9]', '', 'g')
    )
  order by coalesce(profile.display_name, allowed.name);
$$;

revoke all on function public.list_member_directory(text, text) from public, anon;
grant execute on function public.list_member_directory(text, text) to authenticated;

-- 부서장·BEN 팀 내 직책 배정. leadership_role(전체 동아리 권한)은 건드리지 않는다.
update public.member_allowlist
set department = '컴퓨터공학과', student_year = 25, titles = titles || array['밴드부장']
where login_name = '이민섭';

update public.member_allowlist
set department = '국어교육과', student_year = 24, titles = titles || array['연경/대회부장']
where login_name = '이승민';

update public.member_allowlist
set department = '첨단융합학부', student_year = 25,
    titles = titles || array['신입생부장', '벤 주장']
where login_name = '홍성준';

update public.member_allowlist
set titles = titles || array['벤 감독']
where login_name in ('유승준', '임준호', '시유상');

commit;
