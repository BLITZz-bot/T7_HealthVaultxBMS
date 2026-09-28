import type { Alert, AshaWorker, Household, Referral, VisitTask } from './types';

export const DEMO_PHC = { id: 'phc-demo-001', name: 'PHC Hosakote (Demo)' } as const;

const hoursAgo = (h: number) => new Date(Date.now() - h * 3_600_000).toISOString();
const daysFromNow = (d: number) => {
  const t = new Date(Date.now() + d * 86_400_000);
  return `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')}`;
};

export interface MockDb {
  workers: AshaWorker[];
  households: (Household & { ashaId: string })[];
  members: { householdId: string; isPregnant: boolean; isHighRisk: boolean }[];
  alerts: Alert[];
  referrals: Referral[];
  tasks: VisitTask[];
}

export function createMockDb(): MockDb {
  const workers: AshaWorker[] = [
    { id: 'asha-1', fullName: 'Lakshmi Devi', phone: '+91 98450 11001', isActive: true, lastSyncAt: hoursAgo(2), householdCount: 0, villageNames: ['Nandagudi'] },
    { id: 'asha-2', fullName: 'Kavitha R', phone: '+91 98450 11002', isActive: true, lastSyncAt: hoursAgo(20), householdCount: 0, villageNames: ['Sulibele'] },
    { id: 'asha-3', fullName: 'Shobha M', phone: '+91 98450 11003', isActive: true, lastSyncAt: hoursAgo(96), householdCount: 0, villageNames: ['Jadigenahalli'] },
    { id: 'asha-4', fullName: 'Renuka B', phone: '+91 98450 11004', isActive: true, lastSyncAt: hoursAgo(5), householdCount: 0, villageNames: ['Anugondanahalli'] },
    { id: 'asha-5', fullName: 'Manjula K', phone: '+91 98450 11005', isActive: true, lastSyncAt: null, householdCount: 0, villageNames: ['Kumbalahalli'] },
    { id: 'asha-6', fullName: 'Geetha S', phone: null, isActive: false, lastSyncAt: hoursAgo(24 * 40), householdCount: 0, villageNames: ['Nandagudi'] },
  ];

  const heads = [
    'Ramesh Gowda', 'Suresh Kumar', 'Nagaraj H', 'Venkatesh P', 'Manjunath S', 'Ravi Shankar',
    'Anand Rao', 'Prakash N', 'Srinivas M', 'Mahesh B', 'Krishnappa', 'Munirathnam',
    'Chandrashekar', 'Basavaraj', 'Shivanna', 'Harish G', 'Narayanappa', 'Gopal Reddy',
  ];
  const households: MockDb['households'] = heads.map((headName, i) => {
    const w = workers[i % 5];
    return {
      id: `hh-${i + 1}`,
      headName,
      houseNumber: `${100 + i * 7}`,
      villageName: w.villageNames[0],
      ashaId: w.id,
      ashaName: w.fullName,
      memberCount: 2 + (i % 5),
      updatedAt: hoursAgo(i * 9 + 1),
    };
  });

  const members: MockDb['members'] = households.flatMap((h, i) =>
    Array.from({ length: h.memberCount }, (_, j) => ({
      householdId: h.id,
      isPregnant: j === 1 && i % 3 === 0,
      isHighRisk: j === 1 && i % 6 === 0,
    })),
  );

  for (const w of workers) w.householdCount = households.filter((h) => h.ashaId === w.id).length;

  const alerts: Alert[] = [
    { id: 'al-1', type: 'sepsis_risk', severity: 'critical', status: 'open', message: 'Sepsis risk 82% — fever 39.4°C, HR 128, SpO₂ 91%', news2Score: 9, sepsisRisk: 0.82, memberName: 'Savitha Gowda', ashaName: 'Lakshmi Devi', createdAt: hoursAgo(1) },
    { id: 'al-2', type: 'news2_high', severity: 'high', status: 'open', message: 'NEWS2 score 7 — RR 26, SBP 98', news2Score: 7, sepsisRisk: 0.41, memberName: 'Muniyamma', ashaName: 'Kavitha R', createdAt: hoursAgo(4) },
    { id: 'al-3', type: 'high_risk_pregnancy', severity: 'high', status: 'open', message: 'BP 150/100 at 32 weeks — possible pre-eclampsia', news2Score: 3, sepsisRisk: null, memberName: 'Divya N', ashaName: 'Renuka B', createdAt: hoursAgo(7) },
    { id: 'al-4', type: 'news2_high', severity: 'medium', status: 'acknowledged', message: 'NEWS2 score 5 — SpO₂ 94%', news2Score: 5, sepsisRisk: 0.18, memberName: 'Hanumanthappa', ashaName: 'Shobha M', createdAt: hoursAgo(30) },
    { id: 'al-5', type: 'other', severity: 'low', status: 'resolved', message: 'Missed IFA follow-up (2 visits)', news2Score: null, sepsisRisk: null, memberName: 'Pavithra', ashaName: 'Lakshmi Devi', createdAt: hoursAgo(72) },
  ];

  const referrals: Referral[] = [
    { id: 'rf-1', memberName: 'Savitha Gowda', ashaName: 'Lakshmi Devi', reason: 'Suspected sepsis — needs IV antibiotics', facilityName: null, status: 'pending', referredAt: hoursAgo(1), followUpDue: daysFromNow(1) },
    { id: 'rf-2', memberName: 'Divya N', ashaName: 'Renuka B', reason: 'Hypertension in pregnancy', facilityName: 'Taluk Hospital Hosakote', status: 'referred', referredAt: hoursAgo(8), followUpDue: daysFromNow(3) },
    { id: 'rf-3', memberName: 'Baby of Asha K', ashaName: 'Kavitha R', reason: 'Low birth weight (1.9 kg)', facilityName: 'District Hospital SNCU', status: 'admitted', referredAt: hoursAgo(50), followUpDue: daysFromNow(7) },
    { id: 'rf-4', memberName: 'Ramaiah', ashaName: 'Shobha M', reason: 'Uncontrolled diabetes (FBS 260)', facilityName: 'PHC Hosakote', status: 'completed', referredAt: hoursAgo(200), followUpDue: null },
  ];

  const tasks: VisitTask[] = [
    { id: 'tk-1', ashaId: 'asha-1', ashaName: 'Lakshmi Devi', memberName: 'Savitha Gowda', title: 'Re-check vitals after referral', notes: null, dueDate: daysFromNow(1), status: 'pending', createdAt: hoursAgo(1) },
    { id: 'tk-2', ashaId: 'asha-3', ashaName: 'Shobha M', memberName: null, title: 'Sync device — no upload in 4 days', notes: 'Visit PHC Wi-Fi if network is poor.', dueDate: daysFromNow(0), status: 'pending', createdAt: hoursAgo(3) },
    { id: 'tk-3', ashaId: 'asha-2', ashaName: 'Kavitha R', memberName: 'Muniyamma', title: 'Home visit — NEWS2 follow-up', notes: null, dueDate: daysFromNow(-1), status: 'done', createdAt: hoursAgo(40) },
  ];

  return { workers, households, members, alerts, referrals, tasks };
}
