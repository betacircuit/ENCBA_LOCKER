-- 프로필 사진 공유
--
-- 1) avatars 버킷을 public으로 전환한다. 지금까지는 내 프로필을 읽을 때만
--    클라이언트가 스토리지에서 bytes를 내려받아 photoBase64로 썼기 때문에
--    다른 부원의 사진이 어디에서도 보이지 않았다. 버킷을 public으로
--    열면 공개 URL로 누구나(앱 사용자) 사진을 볼 수 있다.
--    URL을 아는 사람만 접근할 수 있는 수준의 공개이며, 클럽 앱 성격상
--    허용하기로 한다. 업로드는 기존 정책대로 본인 폴더에만 가능하다.
-- 2) 멤버 디렉터리 RPC가 avatar_path도 돌려주게 해, 목록·상세 화면이
--    각 멤버의 공개 사진 URL을 바로 만들어 쓸 수 있게 한다.

update storage.buckets
set public = true
where id = 'avatars';

drop function if exists public.list_member_directory(text, text);

create function public.list_member_directory(
  requested_status text default 'all',
  requested_query text default ''
)
returns table(
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
  titles text[],
  avatar_path text
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
    coalesce(nullif(profile.titles, '{}'::text[]), allowed.titles, '{}'::text[]),
    profile.avatar_path
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