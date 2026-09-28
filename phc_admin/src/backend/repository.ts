import type {
  Alert,
  AlertStatus,
  AshaWorker,
  DashboardStats,
  Household,
  LiveTable,
  NewVisitTask,
  Referral,
  ReferralStatus,
  VisitTask,
} from './types';

/**
 * Everything the admin panel reads or writes goes through this interface.
 * Pages never import Supabase directly, so swapping mock → supabase is a
 * one-line env change and every query is forced to be PHC-scoped.
 *
 * Every method takes the phcId from the session. Implementations must throw
 * on failure — never resolve with a "success" that didn't happen.
 */
export interface PhcRepository {
  getDashboardStats(phcId: string): Promise<DashboardStats>;

  listWorkers(phcId: string): Promise<AshaWorker[]>;
  listHouseholds(phcId: string): Promise<Household[]>;

  listAlerts(phcId: string, status: AlertStatus): Promise<Alert[]>;
  /** Changes only the alert's own status — never the patient record. */
  setAlertStatus(phcId: string, alertId: string, status: AlertStatus): Promise<void>;

  listReferrals(phcId: string): Promise<Referral[]>;
  updateReferral(
    phcId: string,
    referralId: string,
    patch: { status: ReferralStatus; facilityName: string | null },
  ): Promise<void>;

  listTasks(phcId: string): Promise<VisitTask[]>;
  createTask(phcId: string, input: NewVisitTask): Promise<void>;
  cancelTask(phcId: string, taskId: string): Promise<void>;

  /** Calls `onChange` when a row in `table` changes (by this panel or an ASHA device). Returns an unsubscribe fn. */
  subscribe(phcId: string, table: LiveTable, onChange: () => void): () => void;
}
