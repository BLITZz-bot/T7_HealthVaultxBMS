import { useMemo, useState } from 'react';
import { repository } from '@/backend';
import { useLiveQuery } from '@/hooks/useLiveQuery';
import { Card, EmptyState, PageHeader, QueryView } from '@/components/ui';
import { formatRelative } from '@/lib/format';

export function HouseholdsPage() {
  const households = useLiveQuery((phc) => repository.listHouseholds(phc), ['households']);
  const [q, setQ] = useState('');
  const [village, setVillage] = useState('');

  const villages = useMemo(
    () => [...new Set((households.data ?? []).map((h) => h.villageName).filter((v): v is string => !!v))].sort(),
    [households.data],
  );
  const needle = q.trim().toLowerCase();
  const control = 'rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-brand-600';

  return (
    <>
      <PageHeader
        title="Households"
        subtitle="Read-only here — households are registered and edited by ASHAs in the field app."
        actions={
          <>
            <select aria-label="Village" value={village} onChange={(e) => setVillage(e.target.value)} className={control}>
              <option value="">All villages</option>
              {villages.map((v) => (
                <option key={v}>{v}</option>
              ))}
            </select>
            <input type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search head of household…" className={`${control} w-60`} />
          </>
        }
      />
      <Card>
        <QueryView query={households} isEmpty={(d) => d.length === 0} empty={<EmptyState title="No households synced yet" />}>
          {(all) => {
            const list = all.filter(
              (h) => (!village || h.villageName === village) && (!needle || h.headName.toLowerCase().includes(needle)),
            );
            if (list.length === 0) return <EmptyState title="No households match these filters" />;
            return (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[40rem] text-left text-sm">
                  <thead className="border-b border-slate-200 bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
                    <tr>
                      <th className="px-4 py-2.5 font-medium">Head of household</th>
                      <th className="px-4 py-2.5 font-medium">House no.</th>
                      <th className="px-4 py-2.5 font-medium">Village</th>
                      <th className="px-4 py-2.5 font-medium">ASHA</th>
                      <th className="px-4 py-2.5 text-right font-medium">Members</th>
                      <th className="px-4 py-2.5 font-medium">Updated</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {list.map((h) => (
                      <tr key={h.id} className="hover:bg-slate-50">
                        <td className="px-4 py-3 font-medium text-slate-800">{h.headName}</td>
                        <td className="px-4 py-3 text-slate-600">{h.houseNumber ?? '—'}</td>
                        <td className="px-4 py-3 text-slate-600">{h.villageName ?? '—'}</td>
                        <td className="px-4 py-3 text-slate-600">{h.ashaName ?? '—'}</td>
                        <td className="px-4 py-3 text-right tabular-nums text-slate-700">{h.memberCount}</td>
                        <td className="px-4 py-3 text-slate-500">{formatRelative(h.updatedAt)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <p className="border-t border-slate-100 px-4 py-2 text-xs text-slate-400">
                  Showing {list.length} of {all.length}
                </p>
              </div>
            );
          }}
        </QueryView>
      </Card>
    </>
  );
}
