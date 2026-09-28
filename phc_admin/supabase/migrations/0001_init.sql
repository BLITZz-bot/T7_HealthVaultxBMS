-- ════════════════════════════════════════════════════════════════════════
-- T7 HealthVault — shared schema for the ASHA Flutter app + PHC admin panel
--
-- Run once in Supabase → SQL Editor (or `supabase db push`). Nothing here
-- has been applied yet; it is the starting contract both clients code against.
--
-- Data flow (bidirectional):
--   ASHA app  → households, members, vitals, alerts, referrals   (upsert on sync)
--   PHC panel → alert status, referral status, visit_tasks        (ASHA app pulls)
--
-- Security model: EVERYTHING is enforced by Row Level Security.
--   • Every row carries phc_id. Users only ever see rows of their own PHC.
--   • ASHA users see/write only rows where asha_id = auth.uid().
--   • PHC staff (phc_admin, medical_officer) read all rows of their PHC and
--     can change workflow state (alerts, referrals, tasks) — not clinical data.
--   • Nobody can change their own role / phc_id from a client.
-- ════════════════════════════════════════════════════════════════════════

-- ── Reference data ─────────────────────────────────────────────────────

create table public.phcs (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  name        text not null,
  block       text,
  district    text,
  state       text,
  created_at  timestamptz not null default now()
);

create table public.villages (
  id          uuid primary key default gen_random_uuid(),
  phc_id      uuid not null references public.phcs(id),
  name        text not null,
  code        text,
  latitude    double precision,
  longitude   double precision,
  created_at  timestamptz not null default now()
);
create index on public.villages (phc_id);

create type public.staff_role as enum ('asha', 'phc_admin', 'medical_officer');

-- One row per auth user. Created by an admin (dashboard / service role), never by the client.
create table public.profiles (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  phc_id        uuid not null references public.phcs(id),
  role          public.staff_role not null,
  full_name     text not null,
  phone         text,
  is_active     boolean not null default true,
  last_sync_at  timestamptz,               -- written by the ASHA app after each successful sync
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on public.profiles (phc_id, role);

-- ── Clinical data (written by the ASHA app) ────────────────────────────
-- ids are UUIDs generated ON THE DEVICE so offline-created rows can be
-- upserted repeatedly without duplicates. deleted_at = soft delete so
-- deletions also sync.

create table public.households (
  id              uuid primary key default gen_random_uuid(),
  phc_id          uuid not null references public.phcs(id),
  asha_id         uuid not null references public.profiles(user_id),
  village_id      uuid references public.villages(id),
  head_name       text not null,
  house_number    text,
  contact_number  text,
  address         text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index on public.households (phc_id, updated_at);
create index on public.households (asha_id);

create table public.members (
  id                      uuid primary key default gen_random_uuid(),
  household_id            uuid not null references public.households(id),
  phc_id                  uuid not null references public.phcs(id),
  asha_id                 uuid not null references public.profiles(user_id),
  full_name               text not null,
  age                     integer,
  gender                  text,
  relation_to_head        text,
  abha_id                 text,
  mobile_number           text,
  is_pregnant             boolean not null default false,
  lmp_date                date,
  edd_date                date,
  is_high_risk_pregnancy  boolean not null default false,
  is_lactating            boolean not null default false,
  td1_vaccine             boolean not null default false,
  td2_vaccine             boolean not null default false,
  td_booster              boolean not null default false,
  ifa_tablets_given       integer not null default 0,
  calcium_tablets_given   integer not null default 0,
  birth_weight            numeric,
  delivery_type           text,
  muac_cm                 numeric,
  has_chronic_condition   boolean not null default false,
  chronic_notes           text,
  latest_news2_score      integer,
  latest_sepsis_risk      numeric,          -- 0..1
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  deleted_at              timestamptz
);
create index on public.members (phc_id, updated_at);
create index on public.members (household_id);

create table public.vitals (
  id                        uuid primary key default gen_random_uuid(),
  member_id                 uuid not null references public.members(id),
  phc_id                    uuid not null references public.phcs(id),
  asha_id                   uuid not null references public.profiles(user_id),
  bp_systolic               integer,
  bp_diastolic              integer,
  temperature_c             numeric,
  pulse_rate                integer,
  spo2                      integer,
  respiratory_rate          integer,
  blood_sugar_fasting       numeric,
  blood_sugar_postprandial  numeric,
  news2_score               integer,
  sepsis_risk               numeric,
  notes                     text,
  device_id                 text,
  recorded_at               timestamptz not null,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);
create index on public.vitals (member_id, recorded_at desc);
create index on public.vitals (phc_id, updated_at);

-- ── Workflow data (both directions) ────────────────────────────────────

-- Raised by the ASHA app (NEWS2 / sepsis engine) → triaged by the PHC.
-- Alert status is separate from the patient record on purpose: resolving an
-- alert must never overwrite clinical state.
create table public.alerts (
  id               uuid primary key default gen_random_uuid(),
  phc_id           uuid not null references public.phcs(id),
  asha_id          uuid not null references public.profiles(user_id),
  member_id        uuid references public.members(id),
  type             text not null check (type in ('news2_high','sepsis_risk','high_risk_pregnancy','other')),
  severity         text not null check (severity in ('low','medium','high','critical')),
  message          text not null,
  news2_score      integer,
  sepsis_risk      numeric,
  status           text not null default 'open' check (status in ('open','acknowledged','resolved')),
  acknowledged_by  uuid references public.profiles(user_id),
  acknowledged_at  timestamptz,
  resolved_by      uuid references public.profiles(user_id),
  resolved_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index on public.alerts (phc_id, status, created_at desc);

create table public.referrals (
  id             uuid primary key default gen_random_uuid(),
  phc_id         uuid not null references public.phcs(id),
  asha_id        uuid not null references public.profiles(user_id),
  member_id      uuid references public.members(id),
  reason         text not null,
  facility_name  text,
  status         text not null default 'pending'
                 check (status in ('pending','referred','admitted','completed','cancelled')),
  referred_at    timestamptz not null default now(),
  follow_up_due  date,
  updated_by     uuid references public.profiles(user_id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint facility_required check (status not in ('referred','admitted') or facility_name is not null)
);
create index on public.referrals (phc_id, status);

-- Created by the PHC → pulled by the ASHA app → marked done on the device.
create table public.visit_tasks (
  id          uuid primary key default gen_random_uuid(),
  phc_id      uuid not null references public.phcs(id),
  asha_id     uuid not null references public.profiles(user_id),
  member_id   uuid references public.members(id),
  title       text not null,
  notes       text,
  due_date    date not null,
  status      text not null default 'pending' check (status in ('pending','done','cancelled')),
  created_by  uuid not null default auth.uid() references public.profiles(user_id),
  done_at     timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index on public.visit_tasks (asha_id, updated_at);
create index on public.visit_tasks (phc_id, status);

-- ── updated_at maintenance (the sync cursor for the Flutter app) ──────

create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['profiles','households','members','vitals','alerts','referrals','visit_tasks'] loop
    execute format('create trigger set_updated_at before update on public.%I
                    for each row execute function public.set_updated_at()', t);
  end loop;
end $$;

-- ── RLS helpers ────────────────────────────────────────────────────────
-- security definer so policies can read profiles without recursing into
-- profiles' own RLS.

create or replace function public.current_phc_id() returns uuid
language sql stable security definer set search_path = public as $$
  select phc_id from public.profiles where user_id = auth.uid() and is_active
$$;

create or replace function public.current_staff_role() returns public.staff_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where user_id = auth.uid() and is_active
$$;

create or replace function public.is_phc_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.current_staff_role() in ('phc_admin','medical_officer'), false)
$$;

-- ── Row Level Security ─────────────────────────────────────────────────

alter table public.phcs        enable row level security;
alter table public.villages    enable row level security;
alter table public.profiles    enable row level security;
alter table public.households  enable row level security;
alter table public.members     enable row level security;
alter table public.vitals      enable row level security;
alter table public.alerts      enable row level security;
alter table public.referrals   enable row level security;
alter table public.visit_tasks enable row level security;

-- phcs / villages: read own PHC; staff manage villages.
create policy phcs_read on public.phcs for select to authenticated
  using (id = public.current_phc_id());

create policy villages_read on public.villages for select to authenticated
  using (phc_id = public.current_phc_id());
create policy villages_staff_write on public.villages for all to authenticated
  using (phc_id = public.current_phc_id() and public.is_phc_staff())
  with check (phc_id = public.current_phc_id() and public.is_phc_staff());

-- profiles: see yourself; staff see everyone in their PHC.
-- Clients may only update phone / last_sync_at on their own row (column grants below).
create policy profiles_read on public.profiles for select to authenticated
  using (user_id = auth.uid() or (public.is_phc_staff() and phc_id = public.current_phc_id()));
create policy profiles_self_update on public.profiles for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke update on public.profiles from authenticated;
grant update (phone, last_sync_at) on public.profiles to authenticated;

-- households / members / vitals: ASHA owns her rows; staff read the PHC.
do $$
declare t text;
begin
  foreach t in array array['households','members','vitals'] loop
    execute format($f$
      create policy %1$s_read on public.%1$I for select to authenticated
        using (phc_id = public.current_phc_id()
               and (public.is_phc_staff() or asha_id = auth.uid()))
    $f$, t);
    execute format($f$
      create policy %1$s_asha_insert on public.%1$I for insert to authenticated
        with check (phc_id = public.current_phc_id() and asha_id = auth.uid()
                    and public.current_staff_role() = 'asha')
    $f$, t);
    execute format($f$
      create policy %1$s_asha_update on public.%1$I for update to authenticated
        using (phc_id = public.current_phc_id() and asha_id = auth.uid())
        with check (phc_id = public.current_phc_id() and asha_id = auth.uid())
    $f$, t);
  end loop;
end $$;

-- alerts: ASHA raises; staff triage.
create policy alerts_read on public.alerts for select to authenticated
  using (phc_id = public.current_phc_id() and (public.is_phc_staff() or asha_id = auth.uid()));
create policy alerts_asha_insert on public.alerts for insert to authenticated
  with check (phc_id = public.current_phc_id() and asha_id = auth.uid());
create policy alerts_staff_update on public.alerts for update to authenticated
  using (phc_id = public.current_phc_id() and public.is_phc_staff())
  with check (phc_id = public.current_phc_id() and public.is_phc_staff());

-- referrals: ASHA creates + updates her own; staff update any in the PHC.
create policy referrals_read on public.referrals for select to authenticated
  using (phc_id = public.current_phc_id() and (public.is_phc_staff() or asha_id = auth.uid()));
create policy referrals_asha_insert on public.referrals for insert to authenticated
  with check (phc_id = public.current_phc_id() and asha_id = auth.uid());
create policy referrals_update on public.referrals for update to authenticated
  using (phc_id = public.current_phc_id() and (public.is_phc_staff() or asha_id = auth.uid()))
  with check (phc_id = public.current_phc_id() and (public.is_phc_staff() or asha_id = auth.uid()));

-- visit_tasks: staff create/cancel; the assigned ASHA reads + marks done.
-- TODO: restrict the ASHA update to status/done_at with a trigger if needed.
create policy tasks_read on public.visit_tasks for select to authenticated
  using (phc_id = public.current_phc_id() and (public.is_phc_staff() or asha_id = auth.uid()));
create policy tasks_staff_insert on public.visit_tasks for insert to authenticated
  with check (phc_id = public.current_phc_id() and public.is_phc_staff() and created_by = auth.uid()
              and exists (select 1 from public.profiles p
                          where p.user_id = asha_id and p.phc_id = public.current_phc_id() and p.role = 'asha'));
create policy tasks_update on public.visit_tasks for update to authenticated
  using (phc_id = public.current_phc_id() and (public.is_phc_staff() or asha_id = auth.uid()))
  with check (phc_id = public.current_phc_id() and (public.is_phc_staff() or asha_id = auth.uid()));

-- ── Read models for the admin panel ────────────────────────────────────
-- security_invoker = true → the caller's RLS applies to the underlying tables.

create view public.asha_worker_summary with (security_invoker = true) as
select p.user_id as id, p.phc_id, p.full_name, p.phone, p.is_active, p.last_sync_at,
       count(distinct h.id) as household_count,
       coalesce(array_agg(distinct v.name) filter (where v.name is not null), '{}') as village_names
from public.profiles p
left join public.households h on h.asha_id = p.user_id and h.deleted_at is null
left join public.villages v   on v.id = h.village_id
where p.role = 'asha'
group by p.user_id;

create view public.household_summary with (security_invoker = true) as
select h.id, h.phc_id, h.head_name, h.house_number, h.updated_at,
       v.name as village_name, p.full_name as asha_name,
       (select count(*) from public.members m where m.household_id = h.id and m.deleted_at is null) as member_count
from public.households h
left join public.villages v on v.id = h.village_id
left join public.profiles p on p.user_id = h.asha_id
where h.deleted_at is null;

create view public.alert_feed with (security_invoker = true) as
select a.id, a.phc_id, a.type, a.severity, a.status, a.message, a.news2_score, a.sepsis_risk, a.created_at,
       m.full_name as member_name, p.full_name as asha_name
from public.alerts a
left join public.members m  on m.id = a.member_id
left join public.profiles p on p.user_id = a.asha_id;

create view public.referral_feed with (security_invoker = true) as
select r.id, r.phc_id, r.reason, r.facility_name, r.status, r.referred_at, r.follow_up_due,
       m.full_name as member_name, p.full_name as asha_name
from public.referrals r
left join public.members m  on m.id = r.member_id
left join public.profiles p on p.user_id = r.asha_id;

create view public.visit_task_feed with (security_invoker = true) as
select t.id, t.phc_id, t.asha_id, t.title, t.notes, t.due_date, t.status, t.created_at,
       m.full_name as member_name, p.full_name as asha_name
from public.visit_tasks t
left join public.members m  on m.id = t.member_id
left join public.profiles p on p.user_id = t.asha_id;

-- Dashboard counts computed in the database (one round trip, no full-table downloads).
create or replace function public.phc_dashboard_stats() returns json
language sql stable security invoker set search_path = public as $$
  select json_build_object(
    'asha_workers',              (select count(*) from profiles where role = 'asha' and phc_id = current_phc_id()),
    'workers_synced_last_7_days',(select count(*) from profiles where role = 'asha' and phc_id = current_phc_id()
                                                             and last_sync_at > now() - interval '7 days'),
    'households',                (select count(*) from households where deleted_at is null),
    'members',                   (select count(*) from members where deleted_at is null),
    'pregnancies',               (select count(*) from members where deleted_at is null and is_pregnant),
    'high_risk_pregnancies',     (select count(*) from members where deleted_at is null and is_high_risk_pregnancy),
    'open_alerts',               (select count(*) from alerts where status = 'open'),
    'critical_open_alerts',      (select count(*) from alerts where status = 'open' and severity = 'critical'),
    'active_referrals',          (select count(*) from referrals where status in ('pending','referred','admitted')),
    'pending_tasks',             (select count(*) from visit_tasks where status = 'pending')
  )
$$;

-- ── Realtime (panel gets live updates; app can listen while foregrounded) ─
alter publication supabase_realtime add table public.alerts, public.referrals, public.visit_tasks, public.households, public.profiles;
