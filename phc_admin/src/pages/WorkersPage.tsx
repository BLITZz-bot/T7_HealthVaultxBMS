import { useState } from 'react';
import { repository } from '@/backend';
import { useSession } from '@/auth/AuthContext';
import { useLiveQuery } from '@/hooks/useLiveQuery';
import { Badge, Button, Card, EmptyState, InlineError, PageHeader, QueryView } from '@/components/ui';
import { formatDateTime, formatRelative, hoursSince } from '@/lib/format';
import { UserPlus, X } from 'lucide-react';

export function WorkersPage() {
  const session = useSession();
  const workers = useLiveQuery((phc) => repository.listWorkers(phc), ['profiles', 'households']);
  
  const statesQuery = useLiveQuery(() => repository.getStates(), ['states']);
  const districtsQuery = useLiveQuery(() => repository.getDistricts(), ['districts']);
  const areasQuery = useLiveQuery((phc) => repository.getAreas(phc), ['villages']);

  const dbStates = statesQuery.data || [];
  const dbDistricts = districtsQuery.data || [];
  const dbAreas = areasQuery.data || [];

  const [q, setQ] = useState('');
  const [isModalOpen, setIsModalOpen] = useState(false);
  
  // Registration Form State
  const [username, setUsername] = useState('');
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [phone, setPhone] = useState('');
  const [aadhaar, setAadhaar] = useState('');
  const [selectedStateId, setSelectedStateId] = useState('');
  const [selectedDistrictId, setSelectedDistrictId] = useState('');
  const [villages, setVillages] = useState<string[]>([]);
  const [isSaving, setIsSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const needle = q.trim().toLowerCase();

  const handleStateChange = (stateId: string) => {
    setSelectedStateId(stateId);
    setSelectedDistrictId('');
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

    if (villages.length === 0) {
      setFormError('Please assign at least one Jurisdiction Area (Village/Ward) to the worker. (Type it and press Enter)');
      return;
    }

    setIsSaving(true);
    try {
      // 1. Generate unique blockchain wallet for the worker
      let walletAddress, walletPrivateKey;
      try {
        const walletRes = await fetch('https://t7-mst-health-vault.onrender.com/worker/generate', { method: 'POST' });
        if (!walletRes.ok) throw new Error('Failed to generate blockchain wallet');
        const walletData = await walletRes.json();
        walletAddress = walletData.wallet_address;
        walletPrivateKey = walletData.private_key;
      } catch (err: any) {
        setFormError('Blockchain Wallet Error: ' + err.message);
        setIsSaving(false);
        return;
      }

      // 2. Save worker to Supabase with the generated wallet
      const stateObj = dbStates.find(s => s.id === selectedStateId);
      const districtObj = dbDistricts.find(d => d.id === selectedDistrictId);

      await repository.createWorker(session.phcId, {
        username: username.trim(),
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        phone: phone.trim(),
        aadhaar: aadhaar.trim() || undefined,
        state: stateObj ? stateObj.name : 'Unknown',
        district: districtObj ? districtObj.name : 'Unknown',
        villageOrWard: villages.length > 0 ? villages.join(', ') : `${districtObj ? districtObj.name : 'General'} Area`,
        walletAddress,
        walletPrivateKey,
      });

      // Reset and close
      setUsername('');
      setFirstName('');
      setLastName('');
      setPhone('');
      setAadhaar('');
      setVillages([]);
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
                      <th className="px-4 py-2.5 font-medium">Wallet</th>
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
                        <td className="px-4 py-3">
                          {w.walletAddress ? (
                            <div className="inline-flex font-mono text-[11px] bg-slate-100 text-slate-600 px-2 py-1 rounded border border-slate-200">
                              {w.walletAddress.substring(0, 6)}...{w.walletAddress.substring(w.walletAddress.length - 4)}
                            </div>
                          ) : (
                            <span className="text-xs text-slate-400 italic">Unregistered</span>
                          )}
                        </td>
                        <td className="px-4 py-3 text-right">
                          <button
                            type="button"
                            onClick={() => handleToggleStatus(w.id, w.isActive)}
                            className="text-xs font-medium text-slate-500 hover:text-slate-800 mr-3"
                          >
                            {w.isActive ? 'Deactivate' : 'Activate'}
                          </button>
                          <button
                            type="button"
                            onClick={async () => {
                              if (confirm('Are you sure you want to permanently delete this worker?')) {
                                try {
                                  await repository.deleteWorker(session.phcId, w.id);
                                  workers.reload();
                                } catch (err: any) {
                                  alert(err.message || 'Failed to delete worker');
                                }
                              }
                            }}
                            className="text-xs font-medium text-red-500 hover:text-red-700"
                          >
                            Delete
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

              {/* ── State & District Cascading Selectors ── */}
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-700">State *</label>
                  <select
                    value={selectedStateId}
                    onChange={(e) => handleStateChange(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-brand-600"
                  >
                    <option value="">Choose State...</option>
                    {dbStates.sort((a,b)=>a.name.localeCompare(b.name)).map((st) => (
                      <option key={st.id} value={st.id}>
                        {st.name}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-700">District *</label>
                  <select
                    value={selectedDistrictId}
                    onChange={(e) => setSelectedDistrictId(e.target.value)}
                    disabled={!selectedStateId}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-brand-600 disabled:bg-slate-100 disabled:text-slate-400"
                  >
                    <option value="">Choose District...</option>
                    {dbDistricts.filter(d => d.state_id === selectedStateId).sort((a,b)=>a.name.localeCompare(b.name)).map((dst) => (
                      <option key={dst.id} value={dst.id}>
                        {dst.name}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div>
                <label className="mb-1 block text-xs font-medium text-slate-700">Jurisdiction Areas (Select from list)</label>
                <div className="flex flex-wrap gap-2 mb-2">
                  {villages.map((v, i) => (
                    <span key={i} className="inline-flex items-center gap-1 rounded-full bg-brand-50 px-2.5 py-1 text-xs font-medium text-brand-700 border border-brand-200">
                      {v}
                      <button type="button" onClick={() => setVillages(villages.filter((_, idx) => idx !== i))} className="text-brand-500 hover:text-brand-900">
                        <X className="size-3" />
                      </button>
                    </span>
                  ))}
                </div>
                
                <select 
                  disabled={!selectedDistrictId}
                  onChange={(e) => {
                    if (e.target.value && !villages.includes(e.target.value)) {
                      setVillages([...villages, e.target.value]);
                    }
                    e.target.value = '';
                  }}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-600 disabled:bg-slate-100 disabled:text-slate-400"
                >
                  <option value="">-- Select Pre-added Area --</option>
                  {dbAreas.filter(a => a.district_id === selectedDistrictId).sort((a,b)=>a.village_or_ward.localeCompare(b.village_or_ward)).map(area => (
                    <option key={area.id} value={area.village_or_ward}>{area.village_or_ward} ({area.block})</option>
                  ))}
                </select>
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
