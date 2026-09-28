import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { env } from '@/config/env';

let client: SupabaseClient | null = null;

/** Lazily created so mock mode never touches Supabase. */
export function getSupabase(): SupabaseClient {
  if (env.backend !== 'supabase') {
    throw new Error('Supabase client requested while VITE_BACKEND is not "supabase".');
  }
  client ??= createClient(env.supabaseUrl, env.supabaseAnonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      // PHC computers are often shared: keep the session in sessionStorage so
      // closing the tab/browser signs the supervisor out.
      storage: window.sessionStorage,
    },
  });
  return client;
}
