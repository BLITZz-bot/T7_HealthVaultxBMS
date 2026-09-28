import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { Session } from '@/backend/types';
import { authAdapter } from './adapters';

type AuthStatus = 'restoring' | 'signed_out' | 'signed_in';

interface AuthContextValue {
  status: AuthStatus;
  session: Session | null;
  signIn(email: string, password: string): Promise<void>;
  signOut(): Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AuthStatus>('restoring');
  const [session, setSession] = useState<Session | null>(null);

  useEffect(() => {
    let cancelled = false;
    authAdapter.restore().then(
      (s) => {
        if (cancelled) return;
        setSession(s);
        setStatus(s ? 'signed_in' : 'signed_out');
      },
      () => !cancelled && setStatus('signed_out'),
    );
    const off = authAdapter.onSignedOut(() => {
      setSession(null);
      setStatus('signed_out');
    });
    return () => {
      cancelled = true;
      off();
    };
  }, []);

  // signIn does NOT touch `status` while in flight — the login page owns its
  // own spinner, so the router never unmounts mid-login.
  const signIn = useCallback(async (email: string, password: string) => {
    const s = await authAdapter.signIn(email, password);
    setSession(s);
    setStatus('signed_in');
  }, []);

  const signOut = useCallback(async () => {
    try {
      await authAdapter.signOut();
    } finally {
      setSession(null);
      setStatus('signed_out');
    }
  }, []);

  const value = useMemo(() => ({ status, session, signIn, signOut }), [status, session, signIn, signOut]);
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>.');
  return ctx;
}

/** For pages behind <RequireAuth>. There is deliberately no fallback identity. */
export function useSession(): Session {
  const { session } = useAuth();
  if (!session) throw new Error('useSession called without an active session.');
  return session;
}
