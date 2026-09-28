import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { FullPageSpinner } from '@/components/ui';
import { useAuth } from './AuthContext';

export function RequireAuth() {
  const { status } = useAuth();
  const location = useLocation();

  if (status === 'restoring') return <FullPageSpinner />;
  if (status === 'signed_out') return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  return <Outlet />;
}
