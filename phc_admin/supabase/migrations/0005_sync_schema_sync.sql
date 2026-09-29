-- Add missing columns to households, members, vitals to align with mobile app schema
ALTER TABLE public.households
  ADD COLUMN IF NOT EXISTS village_id uuid REFERENCES public.villages(id),
  ADD COLUMN IF NOT EXISTS contact_number text,
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS asha_id uuid REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS age integer,
  ADD COLUMN IF NOT EXISTS relation_to_head text,
  ADD COLUMN IF NOT EXISTS abha_id text,
  ADD COLUMN IF NOT EXISTS mobile_number text,
  ADD COLUMN IF NOT EXISTS lmp_date date,
  ADD COLUMN IF NOT EXISTS edd_date date,
  ADD COLUMN IF NOT EXISTS is_high_risk_pregnancy boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_lactating boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS td1_vaccine boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS td2_vaccine boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS td_booster boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS ifa_tablets_given integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS calcium_tablets_given integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS birth_weight numeric,
  ADD COLUMN IF NOT EXISTS delivery_type text,
  ADD COLUMN IF NOT EXISTS muac_cm numeric,
  ADD COLUMN IF NOT EXISTS has_chronic_condition boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS chronic_notes text,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

ALTER TABLE public.vitals
  ADD COLUMN IF NOT EXISTS asha_id uuid REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS bp_systolic integer,
  ADD COLUMN IF NOT EXISTS bp_diastolic integer,
  ADD COLUMN IF NOT EXISTS temperature_c numeric,
  ADD COLUMN IF NOT EXISTS pulse_rate integer,
  ADD COLUMN IF NOT EXISTS respiratory_rate integer,
  ADD COLUMN IF NOT EXISTS blood_sugar_fasting numeric,
  ADD COLUMN IF NOT EXISTS blood_sugar_postprandial numeric,
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS device_id text;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS profiles_user_id_unique ON public.profiles (user_id);
