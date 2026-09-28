import { Link } from 'react-router-dom';
import { Baby, ClipboardList, Home, Send, Siren, Users } from 'lucide-react';
import { repository } from '@/backend';
import { useSession } from '@/auth/AuthContext';
import { useLiveQuery } from '@/hooks/useLiveQuery';
import { Card, CardHeader, EmptyState, ErrorState, PageHeader, QueryView, StatCard } from '@/components/ui';
import { SeverityBadge } from './AlertsPage';
import { formatRelative, hoursSince } from '@/lib/format';

const STALE_SYNC_HOURS = 72;

export function DashboardPage() {
  const { fullName } = useSession();
  const stats = useLiveQuery((phc) => repository.getDashboardStats(phc), ['alerts', 'referrals', 'visit_tasks', 'households']);
  const alerts = useLiveQuery((phc) => repository.listAlerts(phc, 'open'), ['alerts']);
  const workers = useLiveQuery((phc) => repository.listWorkers(phc), ['profiles']);

  const s = stats.data;

  return (
    <>
      <PageHeader title="Dashboard" subtitle={`Welcome, ${fullName}`} />

      {stats.error ? (
        <Card className="mb-6">
          <ErrorState error={stats.error} onRetry={stats.reload} />
        </Card>
      ) : (
        <div className="mb-6 grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
          <StatCard label="Open alerts" value={s?.openAlerts} hint={s ? `${s.criticalOpenAlerts} critical` : undefined} tone="red" icon={<Siren className="size-4" />} />
          <StatCard label="Active referrals" value={s?.activeReferrals} tone="orange" icon={<Send className="size-4" />} />
          <StatCard label="Pending tasks" value={s?.pendingTasks} tone="amber" icon={<ClipboardList className="size-4" />} />
          <StatCard label="ASHA workers" value={s?.ashaWorkers} hint={s ? `${s.workersSyncedLast7Days} synced in last 7 days` : undefined} tone="brand" icon={<Users className="size-4" />} />
          <StatCard label="Households" value={s?.households} hint={s ? `${s.members} members` : undefined} tone="brand" icon={<Home className="size-4" />} />
          <StatCard label="Pregnancies" value={s?.pregnancies} hint={s ? `${s.highRiskPregnancies} high-risk` : undefined} tone="green" icon={<Baby className="size-4" />} />
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader title="Open risk alerts" action={<Link to="/alerts" className="text-xs font-medium text-brand-700 hover:underline">View all</Link>} />
          <QueryView query={alerts} isEmpty={(d) => d.length === 0} empty={<EmptyState title="No open alerts" />}>
            {(list) => (
              <ul className="divide-y divide-slate-100">
                {list.slice(0, 5).map((a) => (
                  <li key={a.id} className="flex items-start justify-between gap-3 px-4 py-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-slate-800">{a.memberName ?? 'Unknown patient'}</p>
                      <p className="truncate text-xs text-slate-500">{a.message}</p>
                    </div>
                    <div className="flex shrink-0 flex-col items-end gap-1">
                      <SeverityBadge severity={a.severity} />
                      <span className="text-xs text-slate-400">{formatRelative(a.createdAt)}</span>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </QueryView>
        </Card>

        <Card>
          <CardHeader title={`Workers not synced in ${STALE_SYNC_HOURS / 24}+ days`} action={<Link to="/workers" className="text-xs font-medium text-brand-700 hover:underline">All workers</Link>} />
          <QueryView
            query={{ ...workers, data: workers.data?.filter((w) => w.isActive && hoursSince(w.lastSyncAt) > STALE_SYNC_HOURS) }}
            isEmpty={(d) => d.length === 0}
            empty={<EmptyState title="All active workers have synced recently" />}
          >
            {(list) => (
              <ul className="divide-y divide-slate-100">
                {list.map((w) => (
                  <li key={w.id} className="flex items-center justify-between gap-3 px-4 py-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-slate-800">{w.fullName}</p>
                      <p className="truncate text-xs text-slate-500">{w.villageNames.join(', ') || 'No villages yet'}</p>
                    </div>
                    <span className="shrink-0 text-xs text-amber-700">Last sync: {formatRelative(w.lastSyncAt)}</span>
                  </li>
                ))}
              </ul>
            )}
          </QueryView>
        </Card>
      </div>
    </>
  );
}
