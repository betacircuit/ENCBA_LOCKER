alter table public.events
  add column if not exists ob_participant_count smallint not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'events_ob_participant_count_check'
      and conrelid = 'public.events'::regclass
  ) then
    alter table public.events
      add constraint events_ob_participant_count_check
      check (ob_participant_count between 0 and 100);
  end if;
end $$;

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
      or new.badge is distinct from old.badge
      or new.is_schedule_manager is distinct from old.is_schedule_manager
      or new.leadership_role is distinct from old.leadership_role
      or new.name is distinct from old.name
      or new.email is distinct from old.email then
      raise exception 'ENCBA_PROFILE_AUTHORIZATION_FIELDS_ARE_ADMIN_ONLY';
    end if;
  end if;
  return new;
end;
$$;

grant update (display_name, student_year, joined_year, phone, position, jersey_number, avatar_path)
on public.profiles to authenticated;
