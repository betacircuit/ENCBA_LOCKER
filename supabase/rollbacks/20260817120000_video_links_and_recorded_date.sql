begin;

-- 20260817120000_video_links_and_recorded_date.sql 되돌리기.
-- 앞의 네 쿼터는 quarter_1..4 컬럼에 그대로 남아 있으므로, 링크 테이블과
-- recorded_on을 지우면 예전 앱이 다시 동작한다. 5쿼터 이후와 쿼터 미정
-- 링크는 이 롤백에서 사라진다.

drop function if exists public.set_video_links(uuid, jsonb);

alter table public.video_comments drop column if exists link_id;

alter table public.video_comments
  drop constraint if exists video_comments_quarter_number_check;
alter table public.video_comments
  add constraint video_comments_quarter_number_check
  check (quarter_number is null or quarter_number between 1 and 4);

drop table if exists public.video_links;

alter table public.videos drop constraint if exists videos_recorded_on_check;
alter table public.videos drop column if exists recorded_on;

revoke update on public.videos from authenticated;
grant update (
  title, category, source_url, youtube_id, source_type,
  quarter_1_url, quarter_2_url, quarter_3_url, quarter_4_url, duration_seconds,
  audience_type, audience_values
) on public.videos to authenticated;

grant insert (video_id, profile_id, quarter_number, timestamp_seconds, body)
  on public.video_comments to authenticated;
grant update (quarter_number) on public.video_comments to authenticated;

-- 20260813173335의 이름만 돌려주던 정의로 되돌린다.
drop function if exists public.list_video_review_players(uuid[]);
create function public.list_video_review_players(
  requested_video_ids uuid[]
)
returns table (video_id uuid, directory_id text, name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if coalesce(cardinality(requested_video_ids), 0) > 50 then
    raise exception 'too many videos requested' using errcode = '22023';
  end if;

  return query
  select
    link.video_id,
    coalesce(
      allowed.consumed_by::text,
      'allowlist:' || allowed.id::text
    ) as directory_id,
    coalesce(profile.display_name, allowed.name) as name
  from public.video_review_players link
  join public.videos video on video.id = link.video_id
  join public.member_allowlist allowed on allowed.id = link.member_allowlist_id
  left join public.profiles profile on profile.id = allowed.consumed_by
  where link.video_id = any(coalesce(requested_video_ids, '{}'::uuid[]))
    and video.category = 'review'
  order by link.video_id, allowed.student_year, allowed.name;
end;
$$;

drop function if exists public.list_video_comment_targets(uuid);
create function public.list_video_comment_targets(
  requested_video_id uuid
)
returns table (comment_id bigint, directory_id text, name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  return query
  select
    target.comment_id,
    coalesce(
      allowed.consumed_by::text,
      'allowlist:' || allowed.id::text
    ) as directory_id,
    coalesce(profile.display_name, allowed.name) as name
  from public.video_comment_targets target
  join public.video_comments comment on comment.id = target.comment_id
  join public.videos video on video.id = comment.video_id
  join public.member_allowlist allowed on allowed.id = target.member_allowlist_id
  left join public.profiles profile on profile.id = allowed.consumed_by
  where comment.video_id = requested_video_id
    and video.category = 'review'
  order by target.comment_id, allowed.student_year, allowed.name;
end;
$$;

revoke all on function public.list_video_review_players(uuid[]) from public, anon;
revoke all on function public.list_video_comment_targets(uuid) from public, anon;
grant execute on function public.list_video_review_players(uuid[]) to authenticated;
grant execute on function public.list_video_comment_targets(uuid) to authenticated;

commit;
