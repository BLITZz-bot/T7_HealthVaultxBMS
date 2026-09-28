import { useState } from 'react';
import { repository, type Alert, type AlertSeverity, type AlertStatus } from '@/backend';
import { useSession } from '@/auth/AuthContext';
import { useLiveQuery } from '@/hooks/useLiveQuery';
import { Badge, Button, Card, EmptyState, InlineError, PageHeader, QueryView, cx } from '@/components/ui';
import { formatDateTime, formatRelative } from '@/lib/format';

const SEVERITY_TONE = { low: 'neutral', medium: 'amber', high: 'orange', critical: 'red' } as const;
const TYPE_LABEL: Record<Alert['type'], string> = {
  news2_high: 'High NEWS2',
  sepsis_risk: 'Sepsis risk',
  high_risk_pregnancy: 'High-risk pregnancy',
  other: 'Other',
};
const TABS: { status: AlertStatus; label: string }[] = [
  { status: 'open', label: 'Open' },
  { status: 'acknowledged', label: 'Acknowledged' },
  { status: 'resolved', label: 'Resolved' },
];

export function SeverityBadge({ severity }: { severity: AlertSeverity }) {
  return <Badge tone={SEVERITY_TONE[severity]}>{severity.toUpperCase()}</Badge>;
}

export function AlertsPage() {
  const [tab, setTab] = useState<AlertStatus>('open');
  const alerts = useLiveQuery((phc) => repository.listAlerts(phc, tab), ['alerts']);

  return (
    <>
      <PageHeader title="Risk alerts" subtitle="Raised automatically by the ASHA app's NEWS2 and sepsis engines." />

      <div role="tablist" className="mb-4 inline-flex rounded-lg border border-slate-200 bg-white p-1">
        {TABS.map((t) => (
          <button
            key={t.status}
            role="tab"
            aria-selected={tab === t.status}
            onClick={() => setTab(t.status)}
            className={cx(
              'rounded-md px-3 py-1.5 text-sm font-medium',
              tab === t.status ? 'bg-brand-700 text-white' : 'text-slate-600 hover:bg-slate-100',
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      <QueryView query={alerts} isEmpty={(d) => d.length === 0} empty={<Card><EmptyState title={`No ${tab} alerts`} /></Card>}>
        {(list) => (
          <div className="grid gap-3">
            {list.map((a) => (
              <AlertCard key={a.id} alert={a} />
            ))}
          </div>
        )}
      </QueryView>
    </>
  );
}

/** Each card owns its own busy/error state, so one item's action never blocks another. */
function AlertCard({ alert }: { alert: Alert }) {
  const { phcId } = useSession();
  const [busy, setBusy] = useState<AlertStatus | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function move(status: AlertStatus) {
    setBusy(status);
    setError(null);
    try {
      await repository.setAlertStatus(phcId, alert.id, status);
      // The live subscription reloads the list; no optimistic removal.
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Update failed.');
      setBusy(null);
    }
  }

  return (
    <Card className="p-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0 space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <SeverityBadge severity={alert.severity} />
            <Badge tone="brand">{TYPE_LABEL[alert.type]}</Badge>
            <span className="text-xs text-slate-400" title={formatDateTime(alert.createdAt)}>
              {formatRelative(alert.createdAt)}
            </span>
          </div>
          <p className="text-sm font-semibold text-slate-900">{alert.memberName ?? 'Unknown patient'}</p>
          <p className="text-sm text-slate-600">{alert.message}</p>
          <p className="text-xs text-slate-500">
            ASHA: {alert.ashaName ?? '—'}
            {alert.news2Score != null && <> · NEWS2 {alert.news2Score}</>}
            {alert.sepsisRisk != null && <> · Sepsis risk {Math.round(alert.sepsisRisk * 100)}%</>}
          </p>
        </div>
        <div className="flex shrink-0 gap-2">
          {alert.status === 'open' && (
            <Button variant="secondary" loading={busy === 'acknowledged'} disabled={busy !== null} onClick={() => void move('acknowledged')}>
              Acknowledge
            </Button>
          )}
          {alert.status !== 'resolved' && (
            <Button loading={busy === 'resolved'} disabled={busy !== null} onClick={() => void move('resolved')}>
              Resolve
            </Button>
          )}
          {alert.status === 'resolved' && (
            <Button variant="ghost" loading={busy === 'open'} disabled={busy !== null} onClick={() => void move('open')}>
              Reopen
            </Button>
          )}
        </div>
      </div>
      {error && (
        <div className="mt-3">
          <InlineError message={error} />
        </div>
      )}
    </Card>
  );
}
