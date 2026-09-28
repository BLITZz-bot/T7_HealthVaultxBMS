import { useState } from 'react';
import { repository } from '@/backend';
import { useLiveQuery } from '@/hooks/useLiveQuery';
import { Badge, Card, EmptyState, PageHeader, QueryView } from '@/components/ui';
import { formatDateTime, formatRelative, hoursSince } from '@/lib/format';

export function WorkersPage() {
  const workers = useLiveQuery((phc) => repository.listWorkers(phc), ['profiles', 'households']);
  const [q, setQ] = useState('');
  const needle = q.trim().toLowerCase();

  return (
    <>
      <PageHeader
        title="ASHA workers"
        subtitle="Workers are added by creating their account in Supabase (see README)."
        actions={
          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search name or village…"
            className="w-64 rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-brand-600"
          />
        }
      />
      <Card>
        <QueryView query={workers} isEmpty={(d) => d.length === 0} empty={<EmptyState title="No ASHA workers in this PHC yet" />}>
          {(all) => {
            const list = needle
              ? all.filter((w) => w.fullName.toLowerCase().includes(needle) || w.villageNames.some((v) => v.toLowerCase().includes(needle)))
              : all;
            if (list.length === 0) return <EmptyState title="No workers match your search" />;
            return (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[40rem] text-left text-sm">
                  <thead className="border-b border-slate-200 bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
                    <tr>
                      <th className="px-4 py-2.5 font-medium">Name</th>
                      <th className="px-4 py-2.5 font-medium">Phone</th>
                      <th className="px-4 py-2.5 font-medium">Villages</th>
                      <th className="px-4 py-2.5 text-right font-medium">Households</th>
                      <th className="px-4 py-2.5 font-medium">Last sync</th>
                      <th className="px-4 py-2.5 font-medium">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {list.map((w) => (
                      <tr key={w.id} className="hover:bg-slate-50">
                        <td className="px-4 py-3 font-medium text-slate-800">{w.fullName}</td>
                        <td className="px-4 py-3 text-slate-600">{w.phone ?? '—'}</td>
                        <td className="px-4 py-3 text-slate-600">{w.villageNames.join(', ') || '—'}</td>
                        <td className="px-4 py-3 text-right tabular-nums text-slate-700">{w.householdCount}</td>
                        <td className="px-4 py-3" title={formatDateTime(w.lastSyncAt)}>
                          <span className={hoursSince(w.lastSyncAt) > 72 ? 'text-amber-700' : 'text-slate-600'}>
                            {formatRelative(w.lastSyncAt)}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          <Badge tone={w.isActive ? 'green' : 'neutral'}>{w.isActive ? 'Active' : 'Inactive'}</Badge>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            );
          }}
        </QueryView>
      </Card>
    </>
  );
}
