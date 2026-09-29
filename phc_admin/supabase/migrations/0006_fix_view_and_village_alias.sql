-- ------------------------------------------------------------------------
-- T7 HealthVault — Migration 0006: fix view and add village_or_ward alias
-- Apply after 0005_sync_schema_sync.sql
-- ------------------------------------------------------------------------

-- Fix: add village_or_ward as a generated column alias for APK compatibility.
-- The APK queries for village_or_ward; the canonical column is `name`.
alter table public.villages
  add column if not exists village_or_ward text generated always as (name) stored;

-- Fix: Recreate asha_worker_summary with correct direct FK join.
-- Previous version used to_jsonb(h)->>'village_id' which is slow and broken.
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
left join public.villages v on v.id = h.village_id
left join public.profile_villages pv on pv.user_id = p.user_id
left join public.villages pv_v on pv_v.id = pv.village_id
where p.role::text = 'asha'
group by p.user_id, p.phc_id, p.full_name, p.phone, p.is_active,
         p.last_sync_at, p.wallet_address;
