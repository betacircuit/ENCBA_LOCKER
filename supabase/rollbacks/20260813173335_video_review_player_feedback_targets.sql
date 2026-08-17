-- Roll back only if clients no longer call these RPCs.
drop function if exists public.list_video_comment_targets(uuid);
drop function if exists public.set_video_comment_targets(bigint, text[]);
drop function if exists public.list_video_review_players(uuid[]);
drop function if exists public.set_video_review_players(uuid, text[]);
drop table if exists public.video_comment_targets;
drop table if exists public.video_review_players;
