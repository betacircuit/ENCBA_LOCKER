-- 일정 공개 대상 직접 선택 · 공지 투표 항목별 인원 제한 · OB 인원 미공개
--
-- 1) 일정을 특정 부원 몇 명에게만 열 수 있게 한다(target_team = '직접 선택').
--    읽기 권한은 UI가 아니라 can_access_event가 최종 판정한다.
-- 2) 공지 투표는 항목마다 정원을 둘 수 있다. 정원이 찬 항목은 서버가 막는다.
-- 3) OB가 참여하지만 몇 명인지 모를 때를 구분해서 저장한다.

begin;

-- 1) 일정 공개 대상 직접 선택 ------------------------------------------------

alter table public.events
  add column if not exists audience_profile_ids uuid[] not null default '{}';

alter table public.events drop constraint if exists events_target_team_check;
alter table public.events
  add constraint events_target_team_check check (
    target_team in ('전체', 'ENCBA', 'BEN', '신입생', '직접 선택')
  );

-- 직접 선택 일정은 팀 소속으로 판정할 수 없다. 팀 기준 함수에서는 관리자만
-- 통과시키고, 실제 대상자 판정은 can_access_event가 맡는다.
create or replace function public.can_view_event(requested_team text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    case
      when requested_team = '직접 선택' then public.is_encba_admin()
      when requested_team = '전체' then true
      else
        public.is_encba_admin()
        or exists (
          select 1
          from public.profile_teams pt
          join public.teams t on t.id = pt.team_id
          where pt.profile_id = (select auth.uid())
            and t.code = case
              when requested_team in ('ENCBA', '신입생') then 'ENCBA'
              else requested_team
            end
        )
    end;
$$;

revoke all on function public.can_view_event(text) from public;
grant execute on function public.can_view_event(text) to authenticated;

create or replace function public.can_access_event(requested_event uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.events e
    where e.id = requested_event
      and (
        case
          when e.target_team = '직접 선택' then
            (select auth.uid()) = any (e.audience_profile_ids)
            or public.is_encba_admin()
          else public.can_view_event(e.target_team)
        end
      )
      and (
        e.visibility = 'team'
        or public.can_manage_schedule()
        or exists (
          select 1 from public.event_roster r
          where r.event_id = e.id
            and r.profile_id = (select auth.uid())
            and r.status = 'confirmed'
        )
      )
  );
$$;

revoke all on function public.can_access_event(uuid) from public;
grant execute on function public.can_access_event(uuid) to authenticated;

-- 2) OB 인원 미공개 -----------------------------------------------------------

-- OB가 오긴 하는데 몇 명인지 모를 때가 있다. 인원 0(=안 옴)과 구분한다.
alter table public.events
  add column if not exists ob_participants_unknown boolean not null default false;

-- 3) 공지 투표 항목별 인원 제한 ------------------------------------------------

-- poll_options와 같은 길이의 배열. 0이면 제한 없음.
alter table public.announcements
  add column if not exists poll_option_limits int[] not null default '{}';

alter table public.announcements
  drop constraint if exists announcements_poll_option_limits_check;
alter table public.announcements
  add constraint announcements_poll_option_limits_check check (
    coalesce(array_length(poll_option_limits, 1), 0) = 0
    or coalesce(array_length(poll_option_limits, 1), 0)
       = coalesce(array_length(poll_options, 1), 0)
  );

-- 정원이 찬 항목에는 투표를 받지 않는다. 화면에서 막는 것과 별개로 서버가
-- 최종 판정해야 동시에 누른 두 사람이 정원을 넘기지 못한다.
create or replace function public.vote_announcement_poll(
  requested_announcement uuid,
  requested_option int
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  limits int[];
  options text[];
  option_limit int;
  current_votes int;
begin
  if auth.uid() is null then
    raise exception 'ENCBA_LOGIN_REQUIRED';
  end if;

  select a.poll_option_limits, a.poll_options
  into limits, options
  from public.announcements a
  where a.id = requested_announcement;

  if not found then
    raise exception 'ENCBA_ANNOUNCEMENT_NOT_FOUND';
  end if;

  if requested_option < 0
    or requested_option >= coalesce(array_length(options, 1), 0) then
    raise exception 'ENCBA_POLL_OPTION_OUT_OF_RANGE';
  end if;

  option_limit := coalesce(limits[requested_option + 1], 0);
  if option_limit > 0 then
    select count(*) into current_votes
    from public.announcement_poll_votes v
    where v.announcement_id = requested_announcement
      and v.option_index = requested_option
      and v.profile_id <> (select auth.uid());
    if current_votes >= option_limit then
      raise exception 'ENCBA_POLL_OPTION_FULL';
    end if;
  end if;

  insert into public.announcement_poll_votes (
    announcement_id, profile_id, option_index
  )
  values (requested_announcement, (select auth.uid()), requested_option)
  on conflict (announcement_id, profile_id)
  do update set option_index = excluded.option_index;
end;
$$;

revoke all on function public.vote_announcement_poll(uuid, int) from public;
grant execute on function public.vote_announcement_poll(uuid, int)
  to authenticated;

notify pgrst, 'reload schema';

commit;
