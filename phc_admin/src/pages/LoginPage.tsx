import { useState, type FormEvent } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';
import { HeartPulse } from 'lucide-react';
import { useAuth } from '@/auth/AuthContext';
import { Button, FullPageSpinner, InlineError } from '@/components/ui';
import { env, isMock } from '@/config/env';

export function LoginPage() {
  const { status, signIn } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from ?? '/';

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (status === 'restoring') return <FullPageSpinner />;
  if (status === 'signed_in') return <Navigate to={from} replace />;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await signIn(email, password);
      navigate(from, { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign-in failed.');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="flex min-h-dvh items-center justify-center bg-gradient-to-br from-brand-900 to-brand-700 px-4">
      <div className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl sm:p-8">
        <div className="mb-6 flex flex-col items-center text-center">
          <span className="mb-3 rounded-xl bg-brand-50 p-2.5">
            <HeartPulse className="size-7 text-brand-700" />
          </span>
          <h1 className="text-xl font-semibold text-slate-900">PHC Admin Panel</h1>
          <p className="mt-1 text-sm text-slate-500">T7 HealthVault — supervisor sign-in</p>
        </div>

        <form onSubmit={onSubmit} className="space-y-4" noValidate>
          <label className="block">
            <span className="mb-1 block text-sm font-medium text-slate-700">Email</span>
            <input
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-600/20"
            />
          </label>
          <label className="block">
            <span className="mb-1 block text-sm font-medium text-slate-700">Password</span>
            <input
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-600 focus:ring-2 focus:ring-brand-600/20"
            />
          </label>

          <InlineError message={error} />

          <Button type="submit" loading={submitting} disabled={!email || !password} className="w-full py-2.5">
            Sign in
          </Button>
        </form>

        {/* Only in mock mode — a Supabase build never renders credentials. */}
        {isMock && (
          <div className="mt-6 rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900">
            <p className="font-semibold">Demo mode (no database connected)</p>
            <p className="mt-1">
              Email: <code>{env.dummyEmail}</code>
              <br />
              Password: <code>{env.dummyPassword}</code>
            </p>
            <button
              type="button"
              onClick={() => {
                setEmail(env.dummyEmail);
                setPassword(env.dummyPassword);
              }}
              className="mt-2 font-medium text-amber-900 underline underline-offset-2"
            >
              Fill demo credentials
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
