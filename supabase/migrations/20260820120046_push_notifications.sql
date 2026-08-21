begin;

alter table public.announcements
  add column if not exists is_urgent boolean not null default false;

grant insert (is_urgent) on public.announcements to authenticated;
grant update (is_urgent) on public.announcements to authenticated;

create table public.push_subscriptions (
  id bigint generated always as identity primary key,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  fcm_token text not null unique
    check (char_length(fcm_token) between 20 and 4096),
  platform text not null
    check (platform in ('web', 'android', 'ios')),
  categories text[] not null
    default array['announcements', 'events', 'videos']::text[]
    check (
      categories <@ array['announcements', 'events', 'videos']::text[]
      and array_position(categories, null) is null
    ),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index push_subscriptions_profile_id_idx
  on public.push_subscriptions (profile_id);

alter table public.push_subscriptions enable row level security;

create policy push_subscriptions_select_own
on public.push_subscriptions for select to authenticated
using ((select auth.uid()) = profile_id);

create policy push_subscriptions_insert_own
on public.push_subscriptions for insert to authenticated
with check ((select auth.uid()) = profile_id);

create policy push_subscriptions_update_own
on public.push_subscriptions for update to authenticated
using ((select auth.uid()) = profile_id)
with check ((select auth.uid()) = profile_id);

create policy push_subscriptions_delete_own
on public.push_subscriptions for delete to authenticated
using ((select auth.uid()) = profile_id);

create trigger push_subscriptions_set_updated_at
before update on public.push_subscriptions
for each row execute function public.set_updated_at();

revoke all on table public.push_subscriptions from public, anon, authenticated;
revoke all on sequence public.push_subscriptions_id_seq from public, anon, authenticated;
grant select, insert, update, delete on table public.push_subscriptions to authenticated;
grant usage on sequence public.push_subscriptions_id_seq to authenticated;
grant select, update on table public.push_subscriptions to service_role;

create table public.push_deliveries (
  id bigint generated always as identity primary key,
  subscription_id bigint not null
    references public.push_subscriptions(id) on delete cascade,
  dedupe_key text not null
    check (char_length(dedupe_key) between 1 and 500),
  created_at timestamptz not null default now(),
  unique (subscription_id, dedupe_key)
);

create index push_deliveries_subscription_id_idx
  on public.push_deliveries (subscription_id);

alter table public.push_deliveries enable row level security;

revoke all on table public.push_deliveries from public, anon, authenticated;
revoke all on sequence public.push_deliveries_id_seq from public, anon, authenticated;
grant select, insert, delete on table public.push_deliveries to service_role;
grant usage on sequence public.push_deliveries_id_seq to service_role;

analyze public.push_subscriptions;
analyze public.push_deliveries;

commit;
