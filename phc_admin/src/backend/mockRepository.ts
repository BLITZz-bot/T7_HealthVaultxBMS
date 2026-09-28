import { createMockDb, DEMO_PHC } from './mockData';
import type { PhcRepository } from './repository';
import type { LiveTable } from './types';

/**
 * In-memory backend for the dummy-login skeleton. Data resets on reload.
 * It behaves like the real one where it matters: async, PHC-scoped, throws on
 * bad input, and notifies subscribers after writes.
 */
const db = createMockDb();
const listeners = new Map<LiveTable, Set<() => void>>();

const delay = (ms = 250) => new Promise((r) => setTimeout(r, ms));
const clone = <T,>(v: T): T => structuredClone(v);
const DAY = 86_400_000;

function assertPhc(phcId: string) {
  if (phcId !== DEMO_PHC.id) throw new Error('Not authorised for this PHC.');
}
function emit(table: LiveTable) {
  listeners.get(table)?.forEach((fn) => fn());
}

export const mockRepository: PhcRepository = {
  async getDashboardStats(phcId) {
    assertPhc(phcId);
    await delay();
    const openAlerts = db.alerts.filter((a) => a.status === 'open');
    return {
      ashaWorkers: db.workers.length,
      workersSyncedLast7Days: db.workers.filter(
        (w) => w.lastSyncAt && Date.now() - Date.parse(w.lastSyncAt) < 7 * DAY,
      ).length,
      households: db.households.length,
      members: db.members.length,
      pregnancies: db.members.filter((m) => m.isPregnant).length,
      highRiskPregnancies: db.members.filter((m) => m.isHighRisk).length,
      openAlerts: openAlerts.length,
      criticalOpenAlerts: openAlerts.filter((a) => a.severity === 'critical').length,
      activeReferrals: db.referrals.filter((r) => ['pending', 'referred', 'admitted'].includes(r.status)).length,
      pendingTasks: db.tasks.filter((t) => t.status === 'pending').length,
    };
  },

  async listWorkers(phcId) {
    assertPhc(phcId);
    await delay();
    return clone(db.workers);
  },

  async createWorker(phcId, input) {
    assertPhc(phcId);
    await delay();
    const fullName = `${input.firstName.trim()} ${input.lastName.trim()}`.trim();
    const newWorker = {
      id: `w-${Date.now()}`,
      fullName,
      phone: input.phone.trim(),
      isActive: true,
      lastSyncAt: null,
      householdCount: 0,
      villageNames: input.villageOrWard ? [input.villageOrWard.trim()] : [],
    };
    db.workers.unshift(newWorker);
    emit('profiles');
    return clone(newWorker);
  },

  async toggleWorkerStatus(phcId, workerId, isActive) {
    assertPhc(phcId);
    await delay();
    const target = db.workers.find((w) => w.id === workerId);
    if (target) {
      target.isActive = isActive;
      emit('profiles');
    }
  },

  async deleteWorker(phcId, workerId) {
    assertPhc(phcId);
    await delay();
    const idx = db.workers.findIndex((w) => w.id === workerId);
    if (idx !== -1) {
      db.workers.splice(idx, 1);
      emit('profiles');
    }
  },

  async listHouseholds(phcId) {
    assertPhc(phcId);
    await delay();
    return clone(db.households.map(({ ashaId: _ashaId, ...h }) => h));
  },

  async listAlerts(phcId, status) {
    assertPhc(phcId);
    await delay();
    return clone(db.alerts.filter((a) => a.status === status));
  },

  async setAlertStatus(phcId, alertId, status) {
    assertPhc(phcId);
    await delay();
    const alert = db.alerts.find((a) => a.id === alertId);
    if (!alert) throw new Error('Alert not found.');
    alert.status = status;
    emit('alerts');
  },

  async listReferrals(phcId) {
    assertPhc(phcId);
    await delay();
    return clone(db.referrals);
  },

  async updateReferral(phcId, referralId, patch) {
    assertPhc(phcId);
    await delay();
    const ref = db.referrals.find((r) => r.id === referralId);
    if (!ref) throw new Error('Referral not found.');
    Object.assign(ref, patch);
    emit('referrals');
  },

  async listTasks(phcId) {
    assertPhc(phcId);
    await delay();
    return clone(db.tasks);
  },

  async createTask(phcId, input) {
    assertPhc(phcId);
    await delay();
    const worker = db.workers.find((w) => w.id === input.ashaId);
    if (!worker) throw new Error('ASHA worker not found in this PHC.');
    db.tasks.unshift({
      id: `tk-${crypto.randomUUID()}`,
      ashaId: worker.id,
      ashaName: worker.fullName,
      memberName: null,
      title: input.title,
      notes: input.notes ?? null,
      dueDate: input.dueDate,
      status: 'pending',
      createdAt: new Date().toISOString(),
    });
    emit('visit_tasks');
  },

  async cancelTask(phcId, taskId) {
    assertPhc(phcId);
    await delay();
    const task = db.tasks.find((t) => t.id === taskId);
    if (!task) throw new Error('Task not found.');
    task.status = 'cancelled';
    emit('visit_tasks');
  },

  subscribe(phcId, table, onChange) {
    assertPhc(phcId);
    const set = listeners.get(table) ?? new Set();
    set.add(onChange);
    listeners.set(table, set);
    return () => {
      set.delete(onChange);
    };
  },
};
