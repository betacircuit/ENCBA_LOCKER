begin;

alter table public.profiles
  add column if not exists is_active boolean not null default true;

alter table public.member_allowlist
  add column if not exists is_active boolean not null default true;

create index if not exists profiles_active_membership_idx
  on public.profiles (is_active, membership_status, name);

create index if not exists allowlist_active_name_idx
  on public.member_allowlist (is_active, name);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  allowlist_enabled boolean;
  allowed_member public.member_allowlist%rowtype;
begin
  select coalesce((value #>> '{}')::boolean, false)
    into allowlist_enabled
    from public.app_settings
    where key = 'enforce_member_allowlist';

  if allowlist_enabled and not exists (
    select 1 from public.member_allowlist a
    where a.login_name = btrim(new.raw_user_meta_data ->> 'name')
      and a.consumed_by is null
      and a.is_active
  ) then
    raise exception 'ENCBA_MEMBER_NOT_ALLOWLISTED_OR_INACTIVE';
  end if;

  select * into allowed_member
  from public.member_allowlist a
  where a.login_name = btrim(new.raw_user_meta_data ->> 'name')
    and a.consumed_by is null
    and a.is_active;

  insert into public.profiles (
    id, email, name, display_name, student_year, generation, phone, position,
    jersey_number, membership_status, badge, is_admin, is_schedule_manager, is_active
  ) values (
    new.id,
    new.email,
    allowed_member.name,
    allowed_member.name,
    coalesce(allowed_member.student_year, (new.raw_user_meta_data ->> 'student_year')::smallint, 0),
    coalesce(allowed_member.generation, (new.raw_user_meta_data ->> 'generation')::smallint, 1),
    coalesce(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'position', '미정'),
    coalesce((new.raw_user_meta_data ->> 'jersey_number')::smallint, 0),
    allowed_member.membership_status,
    case allowed_member.membership_status
      when 'military_leave' then '군복무'
      when 'graduated' then '졸업'
      else null
    end,
    allowed_member.is_admin,
    allowed_member.is_schedule_manager,
    true
  );

  insert into public.profile_teams (profile_id, team_id)
  select new.id, t.id
  from public.teams t
  where t.code = any(coalesce(allowed_member.team_codes, array['ENCBA']::text[]));

  update public.member_allowlist
  set consumed_by = new.id, consumed_at = now()
  where id = allowed_member.id and consumed_by is null;
  return new;
end;
$$;

alter table public.events
  alter column memo set default '',
  drop constraint if exists events_kind_check,
  drop constraint if exists events_target_team_check,
  drop constraint if exists events_memo_check;

update public.events
set target_team = case target_team
  when 'ENCBA 1부' then 'ENCBA'
  when 'ENCBA 2부' then 'BEN'
  else target_team
end
where target_team in ('ENCBA 1부', 'ENCBA 2부');

alter table public.events
  add constraint events_kind_check check (kind in (
    'training', 'morning', 'internal', 'pickup', 'ib_division_1', 'ib_division_2',
    'ib_freshman', 'scrimmage', 'three_way', 'external', 'operation', 'homecoming'
  )),
  add constraint events_target_team_check check (
    target_team in ('전체', 'ENCBA', 'BEN', '신입생')
  ),
  add constraint events_memo_check check (char_length(memo) <= 5000);

insert into public.app_settings (key, value)
values ('ib_team_divisions', '{"ENCBA": 2, "BEN": 2, "신입생": 2}'::jsonb)
on conflict (key) do update
set value = excluded.value, updated_at = now();

create or replace function public.protect_profile_authorization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then return new; end if;
  if not public.is_encba_admin() then
    if new.is_admin is distinct from old.is_admin
      or new.is_active is distinct from old.is_active
      or new.membership_status is distinct from old.membership_status
      or new.generation is distinct from old.generation
      or new.student_year is distinct from old.student_year
      or new.badge is distinct from old.badge
      or new.is_schedule_manager is distinct from old.is_schedule_manager
      or new.name is distinct from old.name
      or new.email is distinct from old.email then
      raise exception 'ENCBA_PROFILE_AUTHORIZATION_FIELDS_ARE_ADMIN_ONLY';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.can_view_event(requested_team text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    requested_team = '전체'
    or public.is_encba_admin()
    or exists (
      select 1
      from public.profile_teams pt
      join public.teams t on t.id = pt.team_id
      where pt.profile_id = (select auth.uid())
        and t.code = case
          when requested_team in ('ENCBA', '신입생') then 'ENCBA'
          else requested_team
        end
    );
$$;

revoke all on function public.can_view_event(text) from public;
grant execute on function public.can_view_event(text) to authenticated;

drop function if exists public.list_member_directory(text, text);
create function public.list_member_directory(
  requested_status text default 'all',
  requested_query text default ''
)
returns table (
  directory_id text,
  name text,
  student_year smallint,
  membership_status public.membership_status,
  is_active boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(p.id::text, 'allowlist:' || a.id::text),
    coalesce(p.display_name, a.name),
    coalesce(p.student_year, a.student_year),
    coalesce(p.membership_status, a.membership_status),
    coalesce(p.is_active, a.is_active)
  from public.member_allowlist a
  left join public.profiles p on p.id = a.consumed_by
  where (select auth.uid()) is not null
    and (
      requested_status = 'all'
      or (requested_status = 'military' and coalesce(p.membership_status, a.membership_status) = 'military_leave')
    )
    and (
      nullif(btrim(requested_query), '') is null
      or coalesce(p.display_name, a.name) ilike '%' || btrim(requested_query) || '%'
      or lpad(coalesce(p.student_year, a.student_year, 0)::text, 2, '0') = regexp_replace(requested_query, '[^0-9]', '', 'g')
    )
  order by coalesce(p.membership_status, a.membership_status) = 'military_leave' desc,
           coalesce(p.display_name, a.name);
$$;

revoke all on function public.list_member_directory(text, text) from public;
grant execute on function public.list_member_directory(text, text) to authenticated;

create or replace function public.set_member_account_active(
  requested_directory_id text,
  requested_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_encba_admin() then
    raise exception 'ENCBA_ADMIN_REQUIRED';
  end if;

  if requested_directory_id = (select auth.uid())::text and not requested_active then
    raise exception 'ENCBA_CANNOT_DISABLE_CURRENT_ADMIN';
  end if;

  if requested_directory_id like 'allowlist:%' then
    update public.member_allowlist
    set is_active = requested_active
    where id = substring(requested_directory_id from 11)::bigint;
  else
    update public.profiles
    set is_active = requested_active
    where id = requested_directory_id::uuid;

    update public.member_allowlist
    set is_active = requested_active
    where consumed_by = requested_directory_id::uuid;
  end if;
end;
$$;

revoke all on function public.set_member_account_active(text, boolean) from public;
grant execute on function public.set_member_account_active(text, boolean) to authenticated;

notify pgrst, 'reload schema';

commit;
