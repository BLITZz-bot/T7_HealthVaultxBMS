-- ════════════════════════════════════════════════════════════════════════
-- T7 HealthVault — Add block column to villages for administrative tracking
-- Apply after 0003_worker_provisioning.sql
-- ════════════════════════════════════════════════════════════════════════

-- Add block column for sub-district/administrative block (e.g., Taluk, Tehsil)
alter table public.villages
  add column if not exists block text;

-- Add a unique constraint on (phc_id, name) to support upsert in provisioning
create unique index if not exists villages_phc_name_unique
  on public.villages (phc_id, lower(name));
create unique index if not exists villages_phc_id_name_unique
  on public.villages (phc_id, name);

-- Update existing villages: set block from any existing code column as a hint
-- (Most villages at this stage are manually curated, so block may be null initially)

-- ════════════════════════════════════════════════════════════════════════
-- Allow PHC staff to insert ASHA worker profiles via the authenticated client
-- (used by the supabaseRepository fallback when the Edge Function is offline).
-- The service-role Edge Function bypasses RLS entirely; this policy covers
-- the direct-DB fallback path.
-- ════════════════════════════════════════════════════════════════════════

-- Staff can insert asha profiles scoped to their own PHC only.
-- user_id auto-generates (gen_random_uuid from migration 0003).
-- role is restricted to 'asha' so staff cannot self-elevate.
drop policy if exists "profiles_staff_insert_asha" on public.profiles;
create policy "profiles_staff_insert_asha"
  on public.profiles
  for insert
  to authenticated
  with check (
    public.is_phc_staff()
    and phc_id = public.current_phc_id()
    and role = 'asha'
    and username is not null
  );

-- Grant insert privilege to authenticated for the columns the fallback sets.
-- role is included but the RLS WITH CHECK restricts it to 'asha' only.
grant insert (phc_id, role, full_name, username, phone, is_active) on public.profiles to authenticated;

