-- ════════════════════════════════════════════════════════════════════════
-- T7 HealthVault — Add States and Districts tables
-- Run this in Supabase → SQL Editor
-- ════════════════════════════════════════════════════════════════════════

-- 1. Create States table
create table if not exists public.states (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

-- 2. Create Districts table
create table if not exists public.districts (
  id uuid primary key default gen_random_uuid(),
  state_id uuid not null references public.states(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  unique(state_id, name)
);

-- 3. Modify existing villages table (if it doesn't already have district_id and village_or_ward)
-- We need to add district_id and rename name to village_or_ward if it's missing.
alter table public.villages 
  add column if not exists district_id uuid references public.districts(id) on delete cascade,
  add column if not exists village_or_ward text;

-- If 'village_or_ward' is new, let's copy over data from 'name'
update public.villages set village_or_ward = name where village_or_ward is null;

-- 4. Enable Row Level Security
alter table public.states enable row level security;
alter table public.districts enable row level security;

-- 5. Create RLS Policies
-- Everyone authenticated can read states and districts
create policy "allow_read_states" on public.states for select to authenticated using (true);
create policy "allow_read_districts" on public.districts for select to authenticated using (true);

-- Only PHC staff can insert/update/delete states
create policy "allow_write_states_staff" on public.states for all to authenticated
using (public.is_phc_staff())
with check (public.is_phc_staff());

-- Only PHC staff can insert/update/delete districts
create policy "allow_write_districts_staff" on public.districts for all to authenticated
using (public.is_phc_staff())
with check (public.is_phc_staff());
