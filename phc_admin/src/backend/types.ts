// Domain types shared by every backend. Field names are camelCase here; the
// Supabase repository maps them from the snake_case columns in
// supabase/migrations/0001_init.sql.

export type StaffRole = 'phc_admin' | 'medical_officer';

/** The single source of truth for "who is logged in and which PHC they own". */
export interface Session {
  userId: string;
  email: string;
  fullName: string;
  role: StaffRole;
  phcId: string;
  phcName: string;
}

export interface DashboardStats {
  ashaWorkers: number;
  workersSyncedLast7Days: number;
  households: number;
  members: number;
  pregnancies: number;
  highRiskPregnancies: number;
  openAlerts: number;
  criticalOpenAlerts: number;
  activeReferrals: number;
  pendingTasks: number;
}

export interface AshaWorker {
  id: string;
  fullName: string;
  phone: string | null;
  isActive: boolean;
  lastSyncAt: string | null;
  householdCount: number;
  villageNames: string[];
  walletAddress: string | null;
}

export interface NewAshaWorker {
  username: string;
  firstName: string;
  lastName: string;
  phone: string;
  aadhaar?: string;
  state?: string;
  district?: string;
  villageOrWard: string;
}

export interface Household {
  id: string;
  headName: string;
  houseNumber: string | null;
  villageName: string | null;
  ashaName: string | null;
  memberCount: number;
  updatedAt: string;
}

export interface State {
  id: string;
  name: string;
}

export interface District {
  id: string;
  state_id: string;
  name: string;
}

export interface Area {
  id: string;
  district_id: string;
  block: string;
  village_or_ward: string;
}


export type AlertSeverity = 'low' | 'medium' | 'high' | 'critical';
export type AlertStatus = 'open' | 'acknowledged' | 'resolved';
export type AlertType = 'news2_high' | 'sepsis_risk' | 'high_risk_pregnancy' | 'other';

export interface Alert {
  id: string;
  type: AlertType;
  severity: AlertSeverity;
  status: AlertStatus;
  message: string;
  news2Score: number | null;
  sepsisRisk: number | null;
  memberName: string | null;
  ashaName: string | null;
  createdAt: string;
}

export type ReferralStatus = 'pending' | 'referred' | 'admitted' | 'completed' | 'cancelled';

export interface Referral {
  id: string;
  memberName: string | null;
  ashaName: string | null;
  reason: string;
  facilityName: string | null;
  status: ReferralStatus;
  referredAt: string;
  followUpDue: string | null;
}

export type TaskStatus = 'pending' | 'done' | 'cancelled';

/** PHC → ASHA direction: tasks created here are pulled by the Flutter app. */
export interface VisitTask {
  id: string;
  ashaId: string;
  ashaName: string | null;
  memberName: string | null;
  title: string;
  notes: string | null;
  dueDate: string;
  status: TaskStatus;
  createdAt: string;
}

export interface NewVisitTask {
  ashaId: string;
  title: string;
  notes?: string;
  dueDate: string; // YYYY-MM-DD
}

/** Tables the UI can receive live-change notifications for. */
export type LiveTable = 'alerts' | 'referrals' | 'visit_tasks' | 'households' | 'profiles' | 'states' | 'districts' | 'villages';
