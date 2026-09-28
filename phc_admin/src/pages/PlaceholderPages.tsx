import { Link } from 'react-router-dom';
import { useSession } from '@/auth/AuthContext';
import { Badge, Card, CardHeader, PageHeader } from '@/components/ui';
import { env } from '@/config/env';

const PLANNED_REPORTS = [
  'Monthly ASHA activity (visits, registrations, vitals recorded)',
  'Maternal health — ANC coverage, high-risk pregnancies, TD/IFA compliance',
  'Child health — birth weight, MUAC / malnutrition',
  'Alert response times (raised → acknowledged → resolved)',
  'Referral outcomes by facility',
  'ASHA stipend / incentive summary (links to on-chain attestation)',
];

export function ReportsPage() {
  return (
    <>
      <PageHeader title="Reports" subtitle="Not built yet — planned reports are listed below." />
      <Card>
        <CardHeader title="Planned" />
        <ul className="divide-y divide-slate-100">
          {PLANNED_REPORTS.map((r) => (
            <li key={r} className="flex items-center justify-between gap-3 px-4 py-3 text-sm text-slate-700">
              {r}
              <Badge>Planned</Badge>
            </li>
          ))}
        </ul>
      </Card>
    </>
  );
}

export function SettingsPage() {
  const session = useSession();
  const rows: [string, string][] = [
    ['Backend', env.backend === 'mock' ? 'Mock (demo data, dummy login)' : 'Supabase'],
    ['Supabase URL', env.backend === 'supabase' ? env.supabaseUrl : 'Not configured'],
    ['Signed in as', `${session.fullName} (${session.email})`],
    ['Role', session.role],
    ['PHC', `${session.phcName} — ${session.phcId}`],
  ];
  return (
    <>
      <PageHeader title="Settings" subtitle="Environment and account details." />
      <Card>
        <CardHeader title="Connection" />
        <dl className="divide-y divide-slate-100">
          {rows.map(([k, v]) => (
            <div key={k} className="grid gap-1 px-4 py-3 text-sm sm:grid-cols-[12rem_1fr]">
              <dt className="text-slate-500">{k}</dt>
              <dd className="break-all text-slate-800">{v}</dd>
            </div>
          ))}
        </dl>
      </Card>
    </>
  );
}

export function NotFoundPage() {
  return (
    <div className="py-20 text-center">
      <p className="text-4xl font-semibold text-slate-300">404</p>
      <p className="mt-2 text-sm text-slate-600">This page doesn't exist.</p>
      <Link to="/" className="mt-4 inline-block text-sm font-medium text-brand-700 hover:underline">
        Back to dashboard
      </Link>
    </div>
  );
}

export function ConfigErrorPage({ errors }: { errors: string[] }) {
  return (
    <div className="flex min-h-dvh items-center justify-center bg-slate-50 px-4">
      <Card className="w-full max-w-lg p-6">
        <h1 className="text-lg font-semibold text-red-700">Configuration error</h1>
        <p className="mt-1 text-sm text-slate-600">The panel can't start until these environment variables are fixed:</p>
        <ul className="mt-3 list-disc space-y-1 pl-5 text-sm text-slate-800">
          {errors.map((e) => (
            <li key={e}>{e}</li>
          ))}
        </ul>
        <p className="mt-4 text-xs text-slate-500">See phc_admin/.env.example. On Vercel, set them in Project → Settings → Environment Variables and redeploy.</p>
      </Card>
    </div>
  );
}
