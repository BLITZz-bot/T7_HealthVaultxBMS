import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { AuthProvider } from '@/auth/AuthContext';
import { RequireAuth } from '@/auth/RequireAuth';
import { AppLayout } from '@/components/AppLayout';
import { AlertsPage } from '@/pages/AlertsPage';
import { DashboardPage } from '@/pages/DashboardPage';
import { HouseholdsPage } from '@/pages/HouseholdsPage';
import { LoginPage } from '@/pages/LoginPage';
import { NotFoundPage, ReportsPage, SettingsPage } from '@/pages/PlaceholderPages';
import { ReferralsPage } from '@/pages/ReferralsPage';
import { TasksPage } from '@/pages/TasksPage';
import { WorkersPage } from '@/pages/WorkersPage';
import { RewardsPage } from '@/pages/RewardsPage';
import { JurisdictionsPage } from '@/pages/JurisdictionsPage';

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route element={<RequireAuth />}>
            <Route element={<AppLayout />}>
              <Route index element={<DashboardPage />} />
              <Route path="alerts" element={<AlertsPage />} />
              <Route path="referrals" element={<ReferralsPage />} />
              <Route path="tasks" element={<TasksPage />} />
              <Route path="workers" element={<WorkersPage />} />
              <Route path="jurisdictions" element={<JurisdictionsPage />} />
              <Route path="households" element={<HouseholdsPage />} />
              <Route path="rewards" element={<RewardsPage />} />
              <Route path="reports" element={<ReportsPage />} />
              <Route path="settings" element={<SettingsPage />} />
              <Route path="*" element={<NotFoundPage />} />
            </Route>
          </Route>
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}
