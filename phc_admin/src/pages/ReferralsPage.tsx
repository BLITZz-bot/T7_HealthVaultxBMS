import { useState } from 'react';
import { repository, type Referral, type ReferralStatus } from '@/backend';
import { useSession } from '@/auth/AuthContext';
import { useLiveQuery } from '@/hooks/useLiveQuery';
import { Badge, Button, Card, EmptyState, InlineError, PageHeader, QueryView } from '@/components/ui';
import { formatDate, formatRelative } from '@/lib/format';

const STATUS_TONE = { pending: 'amber', referred: 'orange', admitted: 'red', completed: 'green', cancelled: 'neutral' } as const;
const STATUSES: ReferralStatus[] = ['pending', 'referred', 'admitted', 'completed', 'cancelled'];
const NEEDS_FACILITY: ReferralStatus[] = ['referred', 'admitted'];

export function ReferralsPage() {
  const referrals = useLiveQuery((phc) => repository.listReferrals(phc), ['referrals']);

  return (
    <>
      <PageHeader title="Referrals" subtitle="Created by ASHAs in the field; tracked to completion by the PHC." />
      <QueryView query={referrals} isEmpty={(d) => d.length === 0} empty={<Card><EmptyState title="No referrals yet" /></Card>}>
        {(list) => (
          <div className="grid gap-3">
            {list.map((r) => (
              <ReferralCard key={r.id} referral={r} />
            ))}
          </div>
        )}
      </QueryView>
    </>
  );
}

function ReferralCard({ referral }: { referral: Referral }) {
  const { phcId } = useSession();
  const [status, setStatus] = useState<ReferralStatus>(referral.status);
  const [facility, setFacility] = useState(referral.facilityName ?? '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const dirty = status !== referral.status || facility.trim() !== (referral.facilityName ?? '');

  async function save() {
    setError(null);
    if (NEEDS_FACILITY.includes(status) && !facility.trim()) {
      setError('Enter the facility name before marking as referred or admitted.');
      return;
    }
    setSaving(true);
    try {
      await repository.updateReferral(phcId, referral.id, { status, facilityName: facility.trim() || null });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Update failed.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card className="p-4">
      <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div className="min-w-0 space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <Badge tone={STATUS_TONE[referral.status]}>{referral.status}</Badge>
            <span className="text-xs text-slate-400">{formatRelative(referral.referredAt)}</span>
          </div>
          <p className="text-sm font-semibold text-slate-900">{referral.memberName ?? 'Unknown patient'}</p>
          <p className="text-sm text-slate-600">{referral.reason}</p>
          <p className="text-xs text-slate-500">
            ASHA: {referral.ashaName ?? '—'} · Follow-up due: {formatDate(referral.followUpDue)}
          </p>
        </div>

        <div className="grid w-full gap-2 sm:grid-cols-[1fr_auto_auto] md:w-auto md:min-w-[26rem]">
          <input
            aria-label="Facility name"
            placeholder={NEEDS_FACILITY.includes(status) ? 'Facility name (required)' : 'Facility name'}
            value={facility}
            onChange={(e) => setFacility(e.target.value)}
            className="rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-600"
          />
          <select
            aria-label="Status"
            value={status}
            onChange={(e) => setStatus(e.target.value as ReferralStatus)}
            className="rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm capitalize outline-none focus:border-brand-600"
          >
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
          <Button onClick={() => void save()} loading={saving} disabled={!dirty}>
            Save
          </Button>
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
