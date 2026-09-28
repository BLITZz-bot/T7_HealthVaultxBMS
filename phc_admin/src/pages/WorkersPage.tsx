import { useState } from 'react';
import { repository } from '@/backend';
import { useSession } from '@/auth/AuthContext';
import { useLiveQuery } from '@/hooks/useLiveQuery';
import { Badge, Button, Card, EmptyState, InlineError, PageHeader, QueryView } from '@/components/ui';
import { formatDateTime, formatRelative, hoursSince } from '@/lib/format';
import { INDIA_STATES_DISTRICTS } from '@/data/indiaData';
import { UserPlus, X } from 'lucide-react';

export function WorkersPage() {
  const session = useSession();
  const workers = useLiveQuery((phc) => repository.listWorkers(phc), ['profiles', 'households']);
  const [q, setQ] = useState('');
  const [isModalOpen, setIsModalOpen] = useState(false);
  
  // Registration Form State
  const [username, setUsername] = useState('');
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [phone, setPhone] = useState('');
  const [aadhaar, setAadhaar] = useState('');
  const [selectedState, setSelectedState] = useState('Karnataka');
  const [selectedDistrict, setSelectedDistrict] = useState(INDIA_STATES_DISTRICTS['Karnataka']?.[0] ?? '');
  const [village, setVillage] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const needle = q.trim().toLowerCase();

  const handleStateChange = (stateName: string) => {
    setSelectedState(stateName);
    const districts = INDIA_STATES_DISTRICTS[stateName] ?? [];
    setSelectedDistrict(districts[0] ?? '');
  };

  const handleRegisterWorker = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);

    if (!username.trim() || !firstName.trim() || !phone.trim()) {
      setFormError('Please enter Username, First Name, and Phone Number.');
      return;
    }

    if (phone.trim().length < 10) {
      setFormError('Please enter a valid 10-digit phone number.');
      return;
    }

    setIsSaving(true);
    try {
      await repository.createWorker(session.phcId, {
        username: username.trim(),
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        phone: phone.trim(),
        aadhaar: aadhaar.trim() || undefined,
        state: selectedState,
        district: selectedDistrict,
        villageOrWard: village.trim() || `${selectedDistrict} Area`,
      });

      // Reset and close
      setUsername('');
      setFirstName('');
      setLastName('');
      setPhone('');
      setAadhaar('');
      setVillage('');
      setIsModalOpen(false);
      workers.reload();
    } catch (err: any) {
      setFormError(err.message || 'Failed to register worker');
    } finally {
      setIsSaving(false);
    }
  };

  const handleToggleStatus = async (workerId: string, currentActive: boolean) => {
    try {
      await repository.toggleWorkerStatus(session.phcId, workerId, !currentActive);
      workers.reload();
    } catch (err: any) {
      alert(err.message || 'Failed to change status');
    }
  };

  return (
    <>
      <PageHeader
        title="ASHA Workers"
        subtitle="Manage field workers, assign jurisdictions, and monitor sync activity."
        actions={
          <div className="flex items-center gap-3">
            <input
              type="search"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Search name, phone, or village…"
              className="w-64 rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-brand-600"
            />
            <Button variant="primary" onClick={() => setIsModalOpen(true)}>
              <UserPlus className="size-4" /> Register Worker
            </Button>
          </div>
        }
      />

      <Card>
        <QueryView query={workers} isEmpty={(d) => d.length === 0} empty={<EmptyState title="No ASHA workers registered yet" />}>
          {(all) => {
            const list = needle
              ? all.filter(
                  (w) =>
                    w.fullName.toLowerCase().includes(needle) ||
                    (w.phone && w.phone.includes(needle)) ||
                    w.villageNames.some((v) => v.toLowerCase().includes(needle)),
                )
              : all;

            if (list.length === 0) return <EmptyState title="No workers match your search" />;

            return (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[44rem] text-left text-sm">
                  <thead className="border-b border-slate-200 bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
                    <tr>
                      <th className="px-4 py-2.5 font-medium">Name</th>
                      <th className="px-4 py-2.5 font-medium">Phone (Login)</th>
                      <th className="px-4 py-2.5 font-medium">Jurisdiction / Villages</th>
                      <th className="px-4 py-2.5 text-right font-medium">Households</th>
                      <th className="px-4 py-2.5 font-medium">Last Sync</th>
                      <th className="px-4 py-2.5 font-medium">Status</th>
                      <th className="px-4 py-2.5 text-right font-medium">Action</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {list.map((w) => (
                      <tr key={w.id} className="hover:bg-slate-50">
                        <td className="px-4 py-3 font-medium text-slate-900">{w.fullName}</td>
                        <td className="px-4 py-3 font-mono text-xs text-slate-600">{w.phone ?? '—'}</td>
                        <td className="px-4 py-3 text-slate-600">{w.villageNames.join(', ') || 'General Ward'}</td>
                        <td className="px-4 py-3 text-right tabular-nums text-slate-700">{w.householdCount}</td>
                        <td className="px-4 py-3" title={formatDateTime(w.lastSyncAt)}>
                          <span className={hoursSince(w.lastSyncAt) > 72 ? 'text-amber-700 font-medium' : 'text-slate-600'}>
                            {formatRelative(w.lastSyncAt)}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          <Badge tone={w.isActive ? 'green' : 'neutral'}>
                            {w.isActive ? 'Active' : 'Inactive'}
                          </Badge>
                        </td>
                        <td className="px-4 py-3 text-right">
                          <button
                            type="button"
                            onClick={() => handleToggleStatus(w.id, w.isActive)}
                            className="text-xs font-medium text-slate-500 hover:text-slate-800"
                          >
                            {w.isActive ? 'Deactivate' : 'Activate'}
                          </button>
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

      {/* ── REGISTER WORKER MODAL (Matches APK Admin) ── */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 p-4 backdrop-blur-xs">
          <div className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-2xl">
            <div className="mb-4 flex items-center justify-between border-b border-slate-100 pb-3">
              <div>
                <h2 className="text-lg font-semibold text-slate-900">Register New ASHA Worker</h2>
                <p className="text-xs text-slate-500">Worker can immediately log into Android APK using Name and Phone.</p>
              </div>
              <button
                type="button"
                onClick={() => setIsModalOpen(false)}
                className="rounded-lg p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-600"
              >
                <X className="size-5" />
              </button>
            </div>

            <form onSubmit={handleRegisterWorker} className="space-y-4">
              <InlineError message={formError} />

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-700">Username *</label>
                  <input
                    type="text"
                    required
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    placeholder="e.g. radha_devi"
                    className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-600"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-700">Phone (Login credential) *</label>
                  <input
                    type="tel"
                    required
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="10-digit mobile"
                    className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-600"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-700">First Name *</label>
                  <input
                    type="text"
                    required
                    value={firstName}
                    onChange={(e) => setFirstName(e.target.value)}
                    placeholder="e.g. Radha"
                    className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-600"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-700">Last Name</label>
                  <input
                    type="text"
                    value={lastName}
                    onChange={(e) => setLastName(e.target.value)}
                    placeholder="e.g. Devi"
                    className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-600"
                  />
                </div>
              </div>

              <div>
                <label className="mb-1 block text-xs font-medium text-slate-700">Aadhaar Number (Optional)</label>
                <input
                  type="text"
                  value={aadhaar}
                  onChange={(e) => setAadhaar(e.target.value)}
                  placeholder="12-digit Aadhaar"
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-600"
                />
              </div>

              {/* ── State & District Cascading Selectors (Matches App IndiaData) ── */}
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-700">State *</label>
                  <select
                    value={selectedState}
                    onChange={(e) => handleStateChange(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-brand-600"
                  >
                    {Object.keys(INDIA_STATES_DISTRICTS).map((st) => (
                      <option key={st} value={st}>
                        {st}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-700">District *</label>
                  <select
                    value={selectedDistrict}
                    onChange={(e) => setSelectedDistrict(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-brand-600"
                  >
                    {(INDIA_STATES_DISTRICTS[selectedState] ?? []).map((dst) => (
                      <option key={dst} value={dst}>
                        {dst}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div>
                <label className="mb-1 block text-xs font-medium text-slate-700">Jurisdiction Village / Ward *</label>
                <input
                  type="text"
                  value={village}
                  onChange={(e) => setVillage(e.target.value)}
                  placeholder="e.g. Hosakote Ward 4, Nandagudi Village"
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-600"
                />
              </div>

              <div className="flex items-center justify-end gap-3 pt-3 border-t border-slate-100">
                <Button variant="secondary" type="button" onClick={() => setIsModalOpen(false)}>
                  Cancel
                </Button>
                <Button variant="primary" type="submit" loading={isSaving}>
                  Save Worker
                </Button>
              </div>
            </form>
          </div>
        </div>
      )}
    </>
  );
}
