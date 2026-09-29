-- Worker-provisioning fields and links used by the admin panel and mobile app.
-- Apply after 0001_init.sql and 0002_jurisdictions.sql.

create or replace function public.current_phc_id() returns uuid
language sql stable security definer set search_path = public as $$
  select phc_id from public.profiles
  where user_id = auth.uid() and is_active
  limit 1
$$;

-- Allow user_id to default to a new UUID and avoid strict FK blocking service-role provisioning
alter table public.profiles alter column user_id set default gen_random_uuid();
alter table public.profiles drop constraint if exists profiles_user_id_fkey;

alter table public.profiles
  add column if not exists username text,
  add column if not exists wallet_address text;

create unique index if not exists profiles_username_unique
  on public.profiles (lower(username)) where username is not null;
create unique index if not exists profiles_wallet_address_unique
  on public.profiles (wallet_address) where wallet_address is not null;

create table if not exists public.profile_villages (
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  village_id uuid not null references public.villages(id) on delete cascade,
  primary key (user_id, village_id)
);
alter table public.profile_villages enable row level security;

drop policy if exists profile_villages_read on public.profile_villages;
create policy profile_villages_read on public.profile_villages for select to authenticated
using (user_id = auth.uid() or (
  public.is_phc_staff() and exists (
    select 1 from public.profiles p
    where p.user_id = profile_villages.user_id and p.phc_id = public.current_phc_id()
  )
));

drop view if exists public.asha_worker_summary;
create or replace view public.asha_worker_summary with (security_invoker = true) as
select p.user_id as id,
       p.phc_id,
       p.full_name,
       p.phone,
       p.is_active,
       p.last_sync_at,
       p.wallet_address,
       count(distinct h.id) as household_count,
       coalesce(
         array_agg(distinct coalesce(pv_v.name, v.name)) filter (where coalesce(pv_v.name, v.name) is not null),
         '{}'
       ) as village_names
from public.profiles p
left join public.households h on h.asha_id = p.user_id
left join public.villages v on v.id::text = to_jsonb(h)->>'village_id'
left join public.profile_villages pv on pv.user_id = p.user_id
left join public.villages pv_v on pv_v.id = pv.village_id
where p.role::text = 'asha'
group by p.user_id;
