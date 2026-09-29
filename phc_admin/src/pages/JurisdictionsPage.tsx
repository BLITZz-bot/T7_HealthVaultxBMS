import { useState, useMemo } from 'react';
import { Trash2, MapPin, Flag, Building2, Download, Search, ChevronDown, ChevronRight, Map, Loader2 } from 'lucide-react';
import { INDIA_STATES_DISTRICTS } from '@/data/indiaData';
import { useSession } from '@/auth/AuthContext';
import { repository } from '@/backend';
import { useLiveQuery } from '@/hooks/useLiveQuery';

export function JurisdictionsPage() {
  const session = useSession();
  
  const statesQuery = useLiveQuery(() => repository.getStates(), ['states']);
  const districtsQuery = useLiveQuery(() => repository.getDistricts(), ['districts']);
  const areasQuery = useLiveQuery((phc) => repository.getAreas(phc), ['villages']);

  const states = statesQuery.data || [];
  const districts = districtsQuery.data || [];
  const areas = areasQuery.data || [];

  const [isSaving, setIsSaving] = useState(false);

  // UI State
  const [searchQuery, setSearchQuery] = useState('');
  const [expandedStates, setExpandedStates] = useState<Set<string>>(new Set());
  const [expandedDistricts, setExpandedDistricts] = useState<Set<string>>(new Set());

  // Modals state
  const [isAddStateOpen, setIsAddStateOpen] = useState(false);
  const [isAddDistrictOpen, setIsAddDistrictOpen] = useState(false);
  const [isAddAreaOpen, setIsAddAreaOpen] = useState(false);

  // Form values
  const [newStateName, setNewStateName] = useState('');
  const [newDistrictStateId, setNewDistrictStateId] = useState('');
  const [newDistrictName, setNewDistrictName] = useState('');
  
  const [newAreaStateId, setNewAreaStateId] = useState('');
  const [newAreaDistrictId, setNewAreaDistrictId] = useState('');
  const [newAreaBlock, setNewAreaBlock] = useState('');
  const [newAreaVillage, setNewAreaVillage] = useState('');

  const loadAllIndiaData = async () => {
    if (!confirm('This will load all predefined States and Districts to your live database. This might take a moment. Continue?')) return;
    
    setIsSaving(true);
    try {
      for (const [stateName, districtNames] of Object.entries(INDIA_STATES_DISTRICTS)) {
        let state = states.find(s => s.name === stateName);
        if (!state) {
          state = await repository.addState(stateName);
        }
        
        for (const dName of districtNames) {
          if (!districts.find(d => d.state_id === state!.id && d.name === dName)) {
            await repository.addDistrict(state!.id, dName);
          }
        }
      }
    } catch (e: any) {
      alert('Error loading data: ' + e.message);
    } finally {
      setIsSaving(false);
      statesQuery.reload();
      districtsQuery.reload();
      areasQuery.reload();
    }
  };

  const handleAddState = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newStateName.trim()) return;
    setIsSaving(true);
    try {
      await repository.addState(newStateName.trim());
      setNewStateName('');
      setIsAddStateOpen(false);
      statesQuery.reload();
    } catch (e: any) { alert(e.message); }
    finally { setIsSaving(false); }
  };

  const handleAddDistrict = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newDistrictName.trim() || !newDistrictStateId) return;
    setIsSaving(true);
    try {
      await repository.addDistrict(newDistrictStateId, newDistrictName.trim());
      setNewDistrictName('');
      setNewDistrictStateId('');
      setExpandedStates(new Set(expandedStates).add(newDistrictStateId));
      setIsAddDistrictOpen(false);
      districtsQuery.reload();
    } catch (e: any) { alert(e.message); }
    finally { setIsSaving(false); }
  };

  const handleAddArea = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newAreaVillage.trim() || !newAreaDistrictId) return;
    setIsSaving(true);
    try {
      await repository.addArea(session.phcId, newAreaDistrictId, newAreaBlock.trim() || 'General', newAreaVillage.trim());
      setNewAreaVillage('');
      setNewAreaBlock('');
      setNewAreaDistrictId('');
      setNewAreaStateId('');
      setExpandedDistricts(new Set(expandedDistricts).add(newAreaDistrictId));
      setIsAddAreaOpen(false);
      areasQuery.reload();
    } catch (e: any) { alert(e.message); }
    finally { setIsSaving(false); }
  };

  const toggleState = (id: string) => {
    const next = new Set(expandedStates);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setExpandedStates(next);
  };

  const toggleDistrict = (id: string) => {
    const next = new Set(expandedDistricts);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setExpandedDistricts(next);
  };

  const deleteState = async (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (confirm('Delete this state and all its districts/areas?')) {
      try { await repository.deleteState(id); } catch(e:any) { alert(e.message); }
    }
  };

  const deleteDistrict = async (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (confirm('Delete this district and its areas?')) {
      try { await repository.deleteDistrict(id); } catch(e:any) { alert(e.message); }
    }
  };

  const deleteArea = async (id: string) => {
    if (confirm('Delete this area?')) {
      try { await repository.deleteArea(id); } catch(e:any) { alert(e.message); }
    }
  };

  // Filter and sort logic
  const filteredStates = useMemo(() => {
    let result = [...states];
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      result = result.filter(s => 
        s.name.toLowerCase().includes(q) || 
        districts.some(d => d.state_id === s.id && d.name.toLowerCase().includes(q))
      );
    }
    return result.sort((a, b) => a.name.localeCompare(b.name));
  }, [states, districts, searchQuery]);

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">Master Jurisdictions</h1>
          <p className="text-sm text-slate-500">Manage States, Districts, and Areas across your network.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <button 
            onClick={loadAllIndiaData}
            disabled={isSaving}
            className="flex items-center gap-2 rounded-lg border border-brand-200 bg-brand-50 px-4 py-2 text-sm font-medium text-brand-700 transition-colors hover:bg-brand-100 mr-2 disabled:opacity-50"
          >
            {isSaving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />} 
            {isSaving ? 'Loading...' : 'Load All States'}
          </button>

          <button onClick={() => setIsAddStateOpen(true)} className="flex items-center gap-2 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-700 shadow-sm transition-colors hover:bg-slate-50 hover:text-slate-900">
            <Flag className="h-4 w-4 text-emerald-600" /> State
          </button>
          <button onClick={() => setIsAddDistrictOpen(true)} className="flex items-center gap-2 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-700 shadow-sm transition-colors hover:bg-slate-50 hover:text-slate-900">
            <Building2 className="h-4 w-4 text-emerald-600" /> District
          </button>
          <button onClick={() => setIsAddAreaOpen(true)} className="flex items-center gap-2 rounded-lg bg-brand-600 px-3 py-2 text-sm font-medium text-white shadow-sm transition-colors hover:bg-brand-700">
            <MapPin className="h-4 w-4" /> Area
          </button>
        </div>
      </div>

      <div className="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden">
        <div className="border-b border-slate-200 bg-slate-50/50 p-4">
          <div className="relative max-w-md">
            <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
              <Search className="h-4 w-4 text-slate-400" />
            </div>
            <input
              type="text"
              className="block w-full rounded-lg border border-slate-300 bg-white py-2 pl-10 pr-3 text-sm placeholder:text-slate-400 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
              placeholder="Search states or districts..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>
        </div>

        <div className="divide-y divide-slate-100">
          {filteredStates.length === 0 ? (
            <div className="p-8 text-center text-sm text-slate-500 flex flex-col items-center">
              <Map className="h-10 w-10 text-slate-300 mb-3" />
              <p>No jurisdictions found matching your criteria.</p>
            </div>
          ) : (
            filteredStates.map(state => {
              const stateDistricts = districts.filter(d => d.state_id === state.id).sort((a,b) => a.name.localeCompare(b.name));
              const isExpanded = expandedStates.has(state.id);
              
              return (
                <div key={state.id} className="group">
                  <div 
                    onClick={() => toggleState(state.id)}
                    className="flex cursor-pointer items-center justify-between p-4 transition-colors hover:bg-slate-50"
                  >
                    <div className="flex items-center gap-3">
                      <div className={`p-1 rounded transition-colors ${isExpanded ? 'bg-brand-100 text-brand-700' : 'text-slate-400 group-hover:text-slate-600'}`}>
                        {isExpanded ? <ChevronDown className="h-5 w-5" /> : <ChevronRight className="h-5 w-5" />}
                      </div>
                      <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700">
                        <Flag className="h-4 w-4" />
                      </div>
                      <div>
                        <h3 className="font-semibold text-slate-900">{state.name}</h3>
                        <p className="text-xs text-slate-500">{stateDistricts.length} Districts assigned</p>
                      </div>
                    </div>
                    <button 
                      onClick={(e) => deleteState(state.id, e)} 
                      className="rounded-lg p-2 text-slate-400 opacity-0 transition-all hover:bg-red-50 hover:text-red-600 group-hover:opacity-100 focus:opacity-100"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                  
                  {isExpanded && (
                    <div className="bg-slate-50/50 px-4 pb-4 pl-16">
                      {stateDistricts.length === 0 ? (
                        <div className="rounded-lg border border-dashed border-slate-300 p-4 text-center text-sm text-slate-500">
                          No districts added yet. Click "Add District" above.
                        </div>
                      ) : (
                        <div className="space-y-2">
                          {stateDistricts.map(district => {
                            const districtAreas = areas.filter(a => a.district_id === district.id).sort((a,b) => a.village_or_ward.localeCompare(b.village_or_ward));
                            const isDistExpanded = expandedDistricts.has(district.id);
                            
                            return (
                              <div key={district.id} className="overflow-hidden rounded-lg border border-slate-200 bg-white shadow-sm transition-all">
                                <div 
                                  onClick={() => toggleDistrict(district.id)}
                                  className="flex cursor-pointer items-center justify-between border-b border-transparent p-3 transition-colors hover:bg-slate-50"
                                >
                                  <div className="flex items-center gap-3">
                                    <div className={`p-0.5 rounded transition-colors ${isDistExpanded ? 'bg-brand-100 text-brand-700' : 'text-slate-400'}`}>
                                      {isDistExpanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                                    </div>
                                    <Building2 className="h-4 w-4 text-emerald-500" />
                                    <span className="font-medium text-slate-800">{district.name}</span>
                                    <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[10px] font-semibold text-slate-600">
                                      {districtAreas.length} AREAS
                                    </span>
                                  </div>
                                  <button 
                                    onClick={(e) => deleteDistrict(district.id, e)} 
                                    className="rounded-md p-1.5 text-slate-400 transition-colors hover:bg-red-50 hover:text-red-600"
                                  >
                                    <Trash2 className="h-3.5 w-3.5" />
                                  </button>
                                </div>
                                
                                {isDistExpanded && (
                                  <div className="border-t border-slate-100 bg-slate-50 p-4">
                                    {districtAreas.length === 0 ? (
                                      <p className="text-sm italic text-slate-400">No areas in this district.</p>
                                    ) : (
                                      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 md:grid-cols-3">
                                        {districtAreas.map(area => (
                                          <div key={area.id} className="group/area flex items-center justify-between rounded-lg border border-slate-200 bg-white p-3 shadow-sm transition-shadow hover:shadow">
                                            <div className="flex flex-col min-w-0">
                                              <span className="truncate font-medium text-slate-800 text-sm">{area.village_or_ward}</span>
                                              <span className="truncate text-xs text-slate-500 mt-0.5">Block: {area.block}</span>
                                            </div>
                                            <button 
                                              onClick={() => deleteArea(area.id)} 
                                              className="ml-2 rounded p-1.5 text-slate-300 transition-colors hover:bg-red-50 hover:text-red-600 group-hover/area:text-red-400"
                                            >
                                              <Trash2 className="h-3.5 w-3.5" />
                                            </button>
                                          </div>
                                        ))}
                                      </div>
                                    )}
                                  </div>
                                )}
                              </div>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>
      </div>

      {/* MODALS */}
      {isAddStateOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-2xl bg-white shadow-2xl overflow-hidden">
            <div className="bg-slate-50 px-6 py-4 border-b border-slate-100 flex items-center gap-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700"><Flag className="h-4 w-4" /></div>
              <h2 className="text-lg font-semibold text-slate-900">Add State</h2>
            </div>
            <form onSubmit={handleAddState} className="p-6">
              <label className="block text-xs font-medium text-slate-700 mb-1.5">State Name</label>
              <input required autoFocus placeholder="e.g. Kerala" value={newStateName} onChange={e => setNewStateName(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 mb-6" />
              <div className="flex justify-end gap-3">
                <button type="button" onClick={() => setIsAddStateOpen(false)} className="rounded-lg px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Cancel</button>
                <button type="submit" disabled={isSaving} className="flex items-center gap-2 rounded-lg bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 shadow-sm disabled:opacity-50">
                  {isSaving && <Loader2 className="h-4 w-4 animate-spin" />} Save State
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {isAddDistrictOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-2xl bg-white shadow-2xl overflow-hidden">
             <div className="bg-slate-50 px-6 py-4 border-b border-slate-100 flex items-center gap-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700"><Building2 className="h-4 w-4" /></div>
              <h2 className="text-lg font-semibold text-slate-900">Add District</h2>
            </div>
            <form onSubmit={handleAddDistrict} className="p-6">
              <label className="block text-xs font-medium text-slate-700 mb-1.5">Select State</label>
              <select required value={newDistrictStateId} onChange={e => setNewDistrictStateId(e.target.value)} className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 mb-4">
                <option value="">Choose...</option>
                {states.sort((a,b)=>a.name.localeCompare(b.name)).map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
              
              <label className="block text-xs font-medium text-slate-700 mb-1.5">District Name</label>
              <input required placeholder="e.g. Malappuram" value={newDistrictName} onChange={e => setNewDistrictName(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 mb-6" />
              
              <div className="flex justify-end gap-3">
                <button type="button" onClick={() => setIsAddDistrictOpen(false)} className="rounded-lg px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Cancel</button>
                <button type="submit" disabled={isSaving} className="flex items-center gap-2 rounded-lg bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 shadow-sm disabled:opacity-50">
                  {isSaving && <Loader2 className="h-4 w-4 animate-spin" />} Save District
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {isAddAreaOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-2xl bg-white shadow-2xl overflow-hidden">
             <div className="bg-slate-50 px-6 py-4 border-b border-slate-100 flex items-center gap-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700"><MapPin className="h-4 w-4" /></div>
              <h2 className="text-lg font-semibold text-slate-900">Add Area / Village</h2>
            </div>
            <form onSubmit={handleAddArea} className="p-6">
              
              <label className="block text-xs font-medium text-slate-700 mb-1.5">Select State</label>
              <select required value={newAreaStateId} onChange={e => { setNewAreaStateId(e.target.value); setNewAreaDistrictId(''); }} className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 mb-4">
                <option value="">Choose State...</option>
                {states.sort((a,b)=>a.name.localeCompare(b.name)).map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>

              <label className="block text-xs font-medium text-slate-700 mb-1.5">Select District</label>
              <select required disabled={!newAreaStateId} value={newAreaDistrictId} onChange={e => setNewAreaDistrictId(e.target.value)} className="w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 mb-4 disabled:bg-slate-100 disabled:text-slate-400">
                <option value="">Choose District...</option>
                {districts.filter(d => d.state_id === newAreaStateId).sort((a,b)=>a.name.localeCompare(b.name)).map(d => <option key={d.id} value={d.id}>{d.name}</option>)}
              </select>
              
              <label className="block text-xs font-medium text-slate-700 mb-1.5">Block / Taluk (Optional)</label>
              <input placeholder="e.g. Hosakote" value={newAreaBlock} onChange={e => setNewAreaBlock(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 mb-4" />
              
              <label className="block text-xs font-medium text-slate-700 mb-1.5">Village or Ward Name</label>
              <input required placeholder="e.g. Nandagudi" value={newAreaVillage} onChange={e => setNewAreaVillage(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500 mb-6" />
              
              <div className="flex justify-end gap-3">
                <button type="button" onClick={() => setIsAddAreaOpen(false)} className="rounded-lg px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">Cancel</button>
                <button type="submit" disabled={isSaving} className="flex items-center gap-2 rounded-lg bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 shadow-sm disabled:opacity-50">
                  {isSaving && <Loader2 className="h-4 w-4 animate-spin" />} Save Area
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
