import { env } from '@/config/env';
import { DEMO_PHC } from '@/backend/mockData';
import type { Session, StaffRole } from '@/backend/types';
import { getSupabase } from '@/lib/supabase';

export interface AuthAdapter {
  /** Restore a session on page load (or null). */
  restore(): Promise<Session | null>;
  signIn(email: string, password: string): Promise<Session>;
  signOut(): Promise<void>;
  /** Notify when the session ends outside our control (expiry, other tab). */
  onSignedOut(cb: () => void): () => void;
}

// ── Dummy (VITE_BACKEND=mock) ──────────────────────────────────────────
// Client-side only: there is no security here, it only lets the skeleton be
// clicked through. Stored in sessionStorage so it ends with the tab.

const DUMMY_KEY = 't7-phc-dummy-session';

const dummySession = (email: string): Session => ({
  userId: 'demo-supervisor',
  email,
  fullName: 'Dr. Demo Supervisor',
  role: 'phc_admin',
  phcId: DEMO_PHC.id,
  phcName: DEMO_PHC.name,
});

function readStorage(): Session | null {
  try {
    const raw = sessionStorage.getItem(DUMMY_KEY);
    return raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    return null;
  }
}

export const dummyAuth: AuthAdapter = {
  async restore() {
    return readStorage();
  },
  async signIn(email, password) {
    await new Promise((r) => setTimeout(r, 400));
    if (email.trim().toLowerCase() !== env.dummyEmail.toLowerCase() || password !== env.dummyPassword) {
      throw new Error('Invalid email or password.');
    }
    const session = dummySession(env.dummyEmail);
    try {
      sessionStorage.setItem(DUMMY_KEY, JSON.stringify(session));
    } catch {
      /* private mode: session just won't survive a reload */
    }
    return session;
  },
  async signOut() {
    try {
      sessionStorage.removeItem(DUMMY_KEY);
    } catch {
      /* ignore */
    }
  },
  onSignedOut() {
    return () => {};
  },
};

// ── Supabase (VITE_BACKEND=supabase) ───────────────────────────────────
// Email + password via Supabase Auth, then the `profiles` row decides the
// role and PHC. ASHA accounts and inactive accounts are refused here, and RLS
// refuses them again on every query.

const STAFF_ROLES: StaffRole[] = ['phc_admin', 'medical_officer'];

async function loadStaffSession(userId: string, email: string): Promise<Session> {
  const sb = getSupabase();
  const { data, error } = await sb
    .from('profiles')
    .select('user_id, full_name, role, phc_id, is_active, phc:phcs(name)')
    .eq('user_id', userId)
    .maybeSingle();

  if (error) throw new Error(error.message);
  if (!data || !data.is_active || !STAFF_ROLES.includes(data.role as StaffRole)) {
    await sb.auth.signOut();
    throw new Error('This account does not have PHC admin access.');
  }
  const phc = (Array.isArray(data.phc) ? data.phc[0] : data.phc) as { name: string } | null;
  return {
    userId: data.user_id as string,
    email,
    fullName: data.full_name as string,
    role: data.role as StaffRole,
    phcId: data.phc_id as string,
    phcName: phc?.name ?? 'Unknown PHC',
  };
}

export const supabaseAuth: AuthAdapter = {
  async restore() {
    const { data } = await getSupabase().auth.getSession();
    const user = data.session?.user;
    if (!user) return null;
    try {
      return await loadStaffSession(user.id, user.email ?? '');
    } catch {
      return null;
    }
  },
  async signIn(email, password) {
    const { data, error } = await getSupabase().auth.signInWithPassword({ email: email.trim(), password });
    if (error) throw new Error(error.message);
    return loadStaffSession(data.user.id, data.user.email ?? email);
  },
  async signOut() {
    await getSupabase().auth.signOut();
  },
  onSignedOut(cb) {
    const { data } = getSupabase().auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') cb();
    });
    return () => data.subscription.unsubscribe();
  },
};

export const authAdapter: AuthAdapter = env.backend === 'supabase' ? supabaseAuth : dummyAuth;
