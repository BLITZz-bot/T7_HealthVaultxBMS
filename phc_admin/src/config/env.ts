export type BackendMode = 'mock' | 'supabase';

const raw = import.meta.env;

const backend = (raw.VITE_BACKEND ?? 'mock').trim().toLowerCase();

/**
 * Problems that must stop the app from booting. We never silently fall back
 * from `supabase` to `mock` — a misconfigured deploy should be obvious, not
 * quietly show demo data to a real supervisor.
 */
export const configErrors: string[] = [];

if (backend !== 'mock' && backend !== 'supabase') {
  configErrors.push(`VITE_BACKEND must be "mock" or "supabase" (got "${backend}").`);
}
if (backend === 'supabase') {
  if (!raw.VITE_SUPABASE_URL) configErrors.push('VITE_SUPABASE_URL is not set.');
  if (!raw.VITE_SUPABASE_ANON_KEY) configErrors.push('VITE_SUPABASE_ANON_KEY is not set.');
}

export const env = {
  backend: backend as BackendMode,
  supabaseUrl: raw.VITE_SUPABASE_URL ?? '',
  supabaseAnonKey: raw.VITE_SUPABASE_ANON_KEY ?? '',
  dummyEmail: raw.VITE_DUMMY_EMAIL || 'supervisor@phc.demo',
  dummyPassword: raw.VITE_DUMMY_PASSWORD || 'demo1234',
} as const;

export const isMock = env.backend === 'mock';
