begin;

-- 복기 영상은 쿼터 4개 고정이었다. 실제로는 연장이 붙거나, 촬영본이 쿼터
-- 경계와 어긋나 "몇 쿼터인지 모르겠는" 클립이 남는다. 링크를 자식 테이블로
-- 옮겨 쿼터 수를 늘리고 쿼터 미정 링크도 담는다. 기존 quarter_1..4 컬럼은
-- 예전 앱이 계속 읽을 수 있도록 남겨 두고, 앞의 네 쿼터는 양쪽에 함께 쓴다.

alter table public.videos
  add column if not exists recorded_on date;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'videos_recorded_on_check'
      and conrelid = 'public.videos'::regclass
  ) then
    alter table public.videos add constraint videos_recorded_on_check
      check (recorded_on is null or recorded_on between date '1977-01-01' and date '2100-12-31');
  end if;
end $$;

create table if not exists public.video_links (
  id bigint generated always as identity primary key,
  video_id uuid not null references public.videos(id) on delete cascade,
  quarter_number smallint check (quarter_number is null or quarter_number between 1 and 12),
  url text not null check (url ~ '^https://' and char_length(url) between 12 and 2000),
  sort_order smallint not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists video_links_video_idx
  on public.video_links (video_id, sort_order, id);

-- 같은 영상에 같은 (쿼터, 링크) 조합이 두 번 들어가지 않게 한다.
-- 쿼터 미정은 -1로 접어서 비교한다.
create unique index if not exists video_links_unique_idx
  on public.video_links (video_id, coalesce(quarter_number, -1::smallint), url);

alter table public.video_links enable row level security;

drop policy if exists video_links_read on public.video_links;
create policy video_links_read on public.video_links for select to authenticated
using (exists (select 1 from public.videos video where video.id = video_id));

-- 링크 편집 권한은 videos_update와 같은 조건을 따른다.
drop policy if exists video_links_manage on public.video_links;
create policy video_links_manage on public.video_links for all to authenticated
using (
  exists (
    select 1 from public.videos video
    where video.id = video_id
      and (
        video.category in ('review', 'shared')
        or (
          video.category = 'highlight'
          and ((select public.is_encba_manager()) or (select public.is_encba_admin()))
        )
      )
  )
)
with check (
  exists (
    select 1 from public.videos video
    where video.id = video_id
      and (
        video.category in ('review', 'shared')
        or (
          video.category = 'highlight'
          and ((select public.is_encba_manager()) or (select public.is_encba_admin()))
        )
      )
  )
);

revoke all on table public.video_links from public, anon;
grant select, insert, update, delete on table public.video_links to authenticated;

-- 기존 쿼터 컬럼을 자식 테이블로 옮긴다. 여러 번 실행해도 안전하다.
insert into public.video_links (video_id, quarter_number, url, sort_order)
select video.id, quarter.number, quarter.url, quarter.number
from public.videos video
cross join lateral (
  values
    (1::smallint, video.quarter_1_url),
    (2::smallint, video.quarter_2_url),
    (3::smallint, video.quarter_3_url),
    (4::smallint, video.quarter_4_url)
) as quarter(number, url)
where quarter.url is not null and quarter.url ~ '^https://'
on conflict do nothing;

-- 코멘트는 이제 "몇 쿼터"가 아니라 "어느 링크"에 붙는다. 쿼터 미정 링크가
-- 여러 개일 때 quarter_number만으로는 구분되지 않기 때문이다.
-- quarter_number는 예전 코멘트와 목록 정렬을 위해 계속 채운다.
alter table public.video_comments
  add column if not exists link_id bigint references public.video_links(id) on delete set null;

create index if not exists video_comments_link_idx
  on public.video_comments (link_id, timestamp_seconds);

alter table public.video_comments
  drop constraint if exists video_comments_quarter_number_check;
alter table public.video_comments
  add constraint video_comments_quarter_number_check
  check (quarter_number is null or quarter_number between 1 and 12);

-- 백필된 링크로 예전 코멘트를 연결한다.
update public.video_comments as comment
set link_id = link.id
from public.video_links as link
where comment.link_id is null
  and comment.quarter_number is not null
  and link.video_id = comment.video_id
  and link.quarter_number = comment.quarter_number;

revoke update on public.videos from authenticated;
grant update (
  title, category, source_url, youtube_id, source_type,
  quarter_1_url, quarter_2_url, quarter_3_url, quarter_4_url, duration_seconds,
  audience_type, audience_values, recorded_on
) on public.videos to authenticated;

grant insert (video_id, profile_id, quarter_number, link_id, timestamp_seconds, body)
  on public.video_comments to authenticated;
grant update (quarter_number, link_id) on public.video_comments to authenticated;

-- 링크 목록을 통째로 바꾼다. 그대로인 링크는 건드리지 않아야 그 링크에
-- 달린 코멘트의 link_id가 살아남는다.
create or replace function public.set_video_links(
  requested_video_id uuid,
  requested_links jsonb default '[]'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  incoming jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(requested_links, '[]'::jsonb)) <> 'array' then
    raise exception 'ENCBA_VIDEO_LINKS_INVALID' using errcode = '22023';
  end if;
  if jsonb_array_length(coalesce(requested_links, '[]'::jsonb)) > 24 then
    raise exception 'ENCBA_VIDEO_LINKS_TOO_MANY' using errcode = '22023';
  end if;

  -- 같은 (쿼터, 링크)가 두 번 들어오면 먼저 나온 순서만 남긴다.
  select coalesce(jsonb_agg(entry order by entry.sort_order), '[]'::jsonb)
    into incoming
  from (
    select distinct on (parsed.quarter_number, parsed.url)
      parsed.quarter_number, parsed.url, parsed.sort_order
    from (
      select
        nullif(item.value ->> 'quarter', '')::smallint as quarter_number,
        btrim(item.value ->> 'url') as url,
        item.ordinality::smallint as sort_order
      from jsonb_array_elements(coalesce(requested_links, '[]'::jsonb))
        with ordinality as item(value, ordinality)
    ) as parsed
    where nullif(parsed.url, '') is not null
    order by parsed.quarter_number, parsed.url, parsed.sort_order
  ) as entry;

  if exists (
    select 1
    from jsonb_to_recordset(incoming)
      as entry(quarter_number smallint, url text, sort_order smallint)
    where entry.url !~ '^https://'
      or char_length(entry.url) > 2000
      or (entry.quarter_number is not null and entry.quarter_number not between 1 and 12)
  ) then
    raise exception 'ENCBA_VIDEO_LINKS_INVALID' using errcode = '22023';
  end if;

  delete from public.video_links as link
  where link.video_id = requested_video_id
    and not exists (
      select 1
      from jsonb_to_recordset(incoming)
        as entry(quarter_number smallint, url text, sort_order smallint)
      where entry.url = link.url
        and entry.quarter_number is not distinct from link.quarter_number
    );

  insert into public.video_links (video_id, quarter_number, url, sort_order)
  select requested_video_id, entry.quarter_number, entry.url, entry.sort_order
  from jsonb_to_recordset(incoming)
    as entry(quarter_number smallint, url text, sort_order smallint)
  on conflict do nothing;

  update public.video_links as link
  set sort_order = entry.sort_order
  from jsonb_to_recordset(incoming)
    as entry(quarter_number smallint, url text, sort_order smallint)
  where link.video_id = requested_video_id
    and entry.url = link.url
    and entry.quarter_number is not distinct from link.quarter_number
    and link.sort_order is distinct from entry.sort_order;
end;
$$;

revoke all on function public.set_video_links(uuid, jsonb) from public, anon;
grant execute on function public.set_video_links(uuid, jsonb) to authenticated;

-- 선수 선택 목록을 학번 높은 순으로 보여주고 등번호를 함께 적으려면
-- 이름 말고 학번·등번호도 내려와야 한다.
drop function if exists public.list_video_review_players(uuid[]);
create function public.list_video_review_players(
  requested_video_ids uuid[]
)
returns table (
  video_id uuid,
  directory_id text,
  name text,
  student_year smallint,
  jersey_number smallint
)
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
    coalesce(profile.display_name, allowed.name) as name,
    coalesce(profile.student_year, allowed.student_year) as student_year,
    coalesce(profile.jersey_number, allowed.jersey_number) as jersey_number
  from public.video_review_players link
  join public.videos video on video.id = link.video_id
  join public.member_allowlist allowed on allowed.id = link.member_allowlist_id
  left join public.profiles profile on profile.id = allowed.consumed_by
  where link.video_id = any(coalesce(requested_video_ids, '{}'::uuid[]))
    and video.category = 'review'
  order by link.video_id,
           coalesce(profile.student_year, allowed.student_year) desc nulls last,
           coalesce(profile.display_name, allowed.name);
end;
$$;

drop function if exists public.list_video_comment_targets(uuid);
create function public.list_video_comment_targets(
  requested_video_id uuid
)
returns table (
  comment_id bigint,
  directory_id text,
  name text,
  student_year smallint,
  jersey_number smallint
)
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
    coalesce(profile.display_name, allowed.name) as name,
    coalesce(profile.student_year, allowed.student_year) as student_year,
    coalesce(profile.jersey_number, allowed.jersey_number) as jersey_number
  from public.video_comment_targets target
  join public.video_comments comment on comment.id = target.comment_id
  join public.videos video on video.id = comment.video_id
  join public.member_allowlist allowed on allowed.id = target.member_allowlist_id
  left join public.profiles profile on profile.id = allowed.consumed_by
  where comment.video_id = requested_video_id
    and video.category = 'review'
  order by target.comment_id,
           coalesce(profile.student_year, allowed.student_year) desc nulls last,
           coalesce(profile.display_name, allowed.name);
end;
$$;

revoke all on function public.list_video_review_players(uuid[]) from public, anon;
revoke all on function public.list_video_comment_targets(uuid) from public, anon;
grant execute on function public.list_video_review_players(uuid[]) to authenticated;
grant execute on function public.list_video_comment_targets(uuid) to authenticated;

analyze public.video_links;

commit;
