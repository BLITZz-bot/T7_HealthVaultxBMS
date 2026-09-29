import type { PostgrestError } from '@supabase/supabase-js';
import { getSupabase } from '@/lib/supabase';
import type { PhcRepository } from './repository';
import type {
  Alert,
  AlertStatus,
  AshaWorker,
  DashboardStats,
  District,
  Household,
  Referral,
  State,
  VisitTask,
} from './types';

/**
 * Real backend. Talks to the views/tables in supabase/migrations/0001_init.sql.
 * RLS already limits every query to the caller's PHC; the explicit
 * `.eq('phc_id', phcId)` filters are defence in depth and help the planner.
 *
 * Not exercised yet — it becomes active when VITE_BACKEND=supabase.
 */

type Row = Record<string, unknown>;

function unwrap<T>(res: { data: T | null; error: PostgrestError | null }): T {
  if (res.error) throw new Error(res.error.message);
  if (res.data === null) throw new Error('No data returned.');
  return res.data;
}

/** For writes: fail if RLS silently matched zero rows. */
function ensureOneRow(res: { data: Row[] | null; error: PostgrestError | null }) {
  const rows = unwrap(res);
  if (rows.length !== 1) throw new Error('Update was not applied (record missing or not permitted).');
}

const str = (v: unknown) => (v == null ? null : String(v));
const num = (v: unknown) => (v == null ? null : Number(v));

export const supabaseRepository: PhcRepository = {
  async getDashboardStats() {
    const s = unwrap(await getSupabase().rpc('phc_dashboard_stats')) as Row;
    return {
      ashaWorkers: Number(s.asha_workers),
      workersSyncedLast7Days: Number(s.workers_synced_last_7_days),
      households: Number(s.households),
      members: Number(s.members),
      pregnancies: Number(s.pregnancies),
      highRiskPregnancies: Number(s.high_risk_pregnancies),
      openAlerts: Number(s.open_alerts),
      criticalOpenAlerts: Number(s.critical_open_alerts),
      activeReferrals: Number(s.active_referrals),
      pendingTasks: Number(s.pending_tasks),
    } satisfies DashboardStats;
  },

  async listWorkers(phcId) {
    const rows = unwrap(
      await getSupabase().from('asha_worker_summary').select('*').eq('phc_id', phcId).order('full_name'),
    ) as Row[];
    return rows.map(
      (r): AshaWorker => ({
        id: String(r.id),
        fullName: String(r.full_name),
        phone: str(r.phone),
        isActive: Boolean(r.is_active),
        lastSyncAt: str(r.last_sync_at),
        householdCount: Number(r.household_count),
        villageNames: (r.village_names as string[] | null) ?? [],
        walletAddress: str(r.wallet_address),
      }),
    );
  },

  async createWorker(phcId, input) {
    const fullName = `${input.firstName.trim()} ${input.lastName.trim()}`.trim();
    const sb = getSupabase();
    const { data, error } = await sb
      .from('profiles')
      .insert({
        phc_id: phcId,
        role: 'asha',
        full_name: fullName,
        username: input.username.trim(),
        phone: input.phone.trim(),
        is_active: true,
        wallet_address: input.walletAddress,
        wallet_private_key: input.walletPrivateKey,
      })
      .select()
      .single();

    if (error) throw new Error(error.message);

    const userId = data.user_id || data.id;
    const villageNames = input.villageOrWard ? input.villageOrWard.split(',').map(v => v.trim()).filter(v => v) : [];
    
    if (villageNames.length > 0) {
      try {
        // 1. Insert villages (ignore duplicates if they exist, but Supabase standard insert returns new rows)
        const { data: insertedVillages, error: vError } = await sb
          .from('villages')
          .insert(villageNames.map(name => ({ phc_id: phcId, name })))
          .select('id');

        if (!vError && insertedVillages) {
          // 2. Link villages to profile
          await sb
            .from('profile_villages')
            .insert(insertedVillages.map(v => ({
              user_id: userId,
              village_id: v.id
            })));
        }
      } catch (e) {
        console.warn('Failed to save villages to Supabase:', e);
      }
    }

    return {
      id: String(data.id),
      fullName: String(data.full_name),
      phone: str(data.phone),
      isActive: true,
      lastSyncAt: null,
      householdCount: 0,
      villageNames: villageNames,
      walletAddress: input.walletAddress ?? null,
    };
  },

  async toggleWorkerStatus(phcId, workerId, isActive) {
    const sb = getSupabase();
    const { error } = await sb
      .from('profiles')
      .update({ is_active: isActive })
      .eq('id', workerId)
      .eq('phc_id', phcId);

    if (error) throw new Error(error.message);
  },

  async deleteWorker(phcId, workerId) {
    const sb = getSupabase();
    const { error } = await sb
      .from('profiles')
      .delete()
      .eq('id', workerId)
      .eq('phc_id', phcId);

    if (error) throw new Error(error.message);
  },

  async listHouseholds(phcId) {
    // TODO: server-side pagination + search once a PHC has thousands of households.
    const rows = unwrap(
      await getSupabase()
        .from('household_summary')
        .select('*')
        .eq('phc_id', phcId)
        .order('updated_at', { ascending: false })
        .limit(500),
    ) as Row[];
    return rows.map(
      (r): Household => ({
        id: String(r.id),
        headName: String(r.head_name),
        houseNumber: str(r.house_number),
        villageName: str(r.village_name),
        ashaName: str(r.asha_name),
        memberCount: Number(r.member_count),
        updatedAt: String(r.updated_at),
      }),
    );
  },

  async listAlerts(phcId, status) {
    const rows = unwrap(
      await getSupabase()
        .from('alert_feed')
        .select('*')
        .eq('phc_id', phcId)
        .eq('status', status)
        .order('created_at', { ascending: false })
        .limit(200),
    ) as Row[];
    return rows.map(
      (r): Alert => ({
        id: String(r.id),
        type: r.type as Alert['type'],
        severity: r.severity as Alert['severity'],
        status: r.status as AlertStatus,
        message: String(r.message),
        news2Score: num(r.news2_score),
        sepsisRisk: num(r.sepsis_risk),
        memberName: str(r.member_name),
        ashaName: str(r.asha_name),
        createdAt: String(r.created_at),
      }),
    );
  },

  async setAlertStatus(phcId, alertId, status) {
    const sb = getSupabase();
    const { data: auth } = await sb.auth.getUser();
    const now = new Date().toISOString();
    const patch: Row = { status };
    if (status === 'acknowledged') Object.assign(patch, { acknowledged_by: auth.user?.id, acknowledged_at: now });
    if (status === 'resolved') Object.assign(patch, { resolved_by: auth.user?.id, resolved_at: now });
    ensureOneRow(await sb.from('alerts').update(patch).eq('id', alertId).eq('phc_id', phcId).select('id'));
  },

  async listReferrals(phcId) {
    const rows = unwrap(
      await getSupabase()
        .from('referral_feed')
        .select('*')
        .eq('phc_id', phcId)
        .order('referred_at', { ascending: false })
        .limit(200),
    ) as Row[];
    return rows.map(
      (r): Referral => ({
        id: String(r.id),
        memberName: str(r.member_name),
        ashaName: str(r.asha_name),
        reason: String(r.reason),
        facilityName: str(r.facility_name),
        status: r.status as Referral['status'],
        referredAt: String(r.referred_at),
        followUpDue: str(r.follow_up_due),
      }),
    );
  },

  async updateReferral(phcId, referralId, patch) {
    const sb = getSupabase();
    const { data: auth } = await sb.auth.getUser();
    ensureOneRow(
      await sb
        .from('referrals')
        .update({ status: patch.status, facility_name: patch.facilityName, updated_by: auth.user?.id })
        .eq('id', referralId)
        .eq('phc_id', phcId)
        .select('id'),
    );
  },

  async listTasks(phcId) {
    const rows = unwrap(
      await getSupabase()
        .from('visit_task_feed')
        .select('*')
        .eq('phc_id', phcId)
        .order('created_at', { ascending: false })
        .limit(200),
    ) as Row[];
    return rows.map(
      (r): VisitTask => ({
        id: String(r.id),
        ashaId: String(r.asha_id),
        ashaName: str(r.asha_name),
        memberName: str(r.member_name),
        title: String(r.title),
        notes: str(r.notes),
        dueDate: String(r.due_date),
        status: r.status as VisitTask['status'],
        createdAt: String(r.created_at),
      }),
    );
  },

  async createTask(phcId, input) {
    const { error } = await getSupabase().from('visit_tasks').insert({
      phc_id: phcId,
      asha_id: input.ashaId,
      title: input.title,
      notes: input.notes || null,
      due_date: input.dueDate,
    });
    if (error) throw new Error(error.message);
  },

  async cancelTask(phcId, taskId) {
    ensureOneRow(
      await getSupabase()
        .from('visit_tasks')
        .update({ status: 'cancelled' })
        .eq('id', taskId)
        .eq('phc_id', phcId)
        .select('id'),
    );
  },

  async getStates() {
    const rows = unwrap(await getSupabase().from('states').select('*').order('name')) as Row[];
    return rows.map((r): State => ({ id: String(r.id), name: String(r.name) }));
  },

  async getDistricts() {
    const rows = unwrap(await getSupabase().from('districts').select('*').order('name')) as Row[];
    return rows.map((r): District => ({ id: String(r.id), state_id: String(r.state_id), name: String(r.name) }));
  },

  async getAreas(phcId) {
    const rows = unwrap(await getSupabase().from('villages').select('*').eq('phc_id', phcId).order('name')) as Row[];
    return rows.map((r): import('./types').Area => ({ 
      id: String(r.id), 
      district_id: str(r.district_id) || '', 
      block: str(r.block) || 'General', 
      village_or_ward: String(r.name) 
    }));
  },

  async addState(name) {
    const { data, error } = await getSupabase().from('states').insert({ name }).select().single();
    if (error) throw new Error(error.message);
    return { id: String(data.id), name: String(data.name) };
  },

  async addDistrict(stateId, name) {
    const { data, error } = await getSupabase().from('districts').insert({ state_id: stateId, name }).select().single();
    if (error) throw new Error(error.message);
    return { id: String(data.id), state_id: String(data.state_id), name: String(data.name) };
  },

  async addArea(phcId, districtId, block, villageName) {
    const { data, error } = await getSupabase().from('villages').insert({ 
      phc_id: phcId,
      district_id: districtId,
      block: block,
      name: villageName 
    }).select().single();
    if (error) throw new Error(error.message);
    return { 
      id: String(data.id), 
      district_id: str(data.district_id) || '', 
      block: str(data.block) || 'General', 
      village_or_ward: String(data.name) 
    };
  },

  async deleteState(id) {
    const { error } = await getSupabase().from('states').delete().eq('id', id);
    if (error) throw new Error(error.message);
  },

  async deleteDistrict(id) {
    const { error } = await getSupabase().from('districts').delete().eq('id', id);
    if (error) throw new Error(error.message);
  },

  async deleteArea(id) {
    const { error } = await getSupabase().from('villages').delete().eq('id', id);
    if (error) throw new Error(error.message);
  },

  subscribe(phcId, table, onChange) {
    const sb = getSupabase();
    const uniqueId = Math.random().toString(36).slice(2, 9);
    const channel = sb
      .channel(`phc-${phcId}-${table}-${uniqueId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table, filter: `phc_id=eq.${phcId}` },
        () => onChange(),
      )
      .subscribe();
    return () => {
      void sb.removeChannel(channel);
    };
  },
};
