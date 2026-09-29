import { useEffect, useState } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import {
  BarChart3,
  ClipboardList,
  HeartPulse,
  Home,
  LayoutDashboard,
  LogOut,
  Menu,
  Send,
  Settings,
  Siren,
  Users,
  Coins,
  MapPin,
  X,
} from 'lucide-react';
import { useAuth, useSession } from '@/auth/AuthContext';
import { isMock } from '@/config/env';
import { cx } from './ui';

const NAV = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/alerts', label: 'Risk alerts', icon: Siren },
  { to: '/referrals', label: 'Referrals', icon: Send },
  { to: '/tasks', label: 'Visit tasks', icon: ClipboardList },
  { to: '/workers', label: 'ASHA workers', icon: Users },
  { to: '/jurisdictions', label: 'Master Jurisdictions', icon: MapPin },
  { to: '/households', label: 'Households', icon: Home },
  { to: '/rewards', label: 'CareCoins', icon: Coins },
  { to: '/reports', label: 'Reports', icon: BarChart3 },
  { to: '/settings', label: 'Settings', icon: Settings },
] as const;

const ROLE_LABEL = { phc_admin: 'PHC Admin', medical_officer: 'Medical Officer' } as const;

function SidebarNav({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <nav className="flex flex-col gap-1 p-3">
      {NAV.map(({ to, label, icon: Icon, ...rest }) => (
        <NavLink
          key={to}
          to={to}
          end={'end' in rest}
          onClick={onNavigate}
          className={({ isActive }) =>
            cx(
              'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
              isActive ? 'bg-brand-700 text-white' : 'text-brand-50/80 hover:bg-brand-800 hover:text-white',
            )
          }
        >
          <Icon className="size-4" />
          {label}
        </NavLink>
      ))}
    </nav>
  );
}

function Brand() {
  return (
    <div className="flex items-center gap-2 px-5 py-4">
      <span className="rounded-lg bg-white/10 p-1.5">
        <HeartPulse className="size-5 text-white" />
      </span>
      <div className="leading-tight">
        <p className="text-sm font-semibold text-white">T7 HealthVault</p>
        <p className="text-xs text-brand-100/70">PHC Admin</p>
      </div>
    </div>
  );
}

export function AppLayout() {
  const session = useSession();
  const { signOut } = useAuth();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const location = useLocation();

  useEffect(() => setDrawerOpen(false), [location.pathname]);

  return (
    <div className="flex min-h-dvh bg-slate-50">
      {/* Desktop sidebar */}
      <aside className="hidden w-60 shrink-0 flex-col bg-brand-900 lg:flex">
        <Brand />
        <SidebarNav />
      </aside>

      {/* Mobile drawer */}
      {drawerOpen && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <button aria-label="Close menu" className="absolute inset-0 bg-slate-900/40" onClick={() => setDrawerOpen(false)} />
          <aside className="relative z-10 flex h-full w-64 flex-col bg-brand-900">
            <div className="flex items-center justify-between pr-3">
              <Brand />
              <button aria-label="Close menu" onClick={() => setDrawerOpen(false)} className="rounded p-1 text-white/80 hover:bg-white/10">
                <X className="size-5" />
              </button>
            </div>
            <SidebarNav onNavigate={() => setDrawerOpen(false)} />
          </aside>
        </div>
      )}

      <div className="flex min-w-0 flex-1 flex-col">
        {isMock && (
          <div className="bg-amber-100 px-4 py-1.5 text-center text-xs font-medium text-amber-900">
            Demo mode — dummy login and sample data. Nothing is saved to a database.
          </div>
        )}
        <header className="flex items-center justify-between gap-3 border-b border-slate-200 bg-white px-4 py-3 sm:px-6">
          <div className="flex min-w-0 items-center gap-3">
            <button aria-label="Open menu" onClick={() => setDrawerOpen(true)} className="rounded p-1 text-slate-600 hover:bg-slate-100 lg:hidden">
              <Menu className="size-5" />
            </button>
            <p className="truncate text-sm font-semibold text-slate-800">{session.phcName}</p>
          </div>
          <div className="flex items-center gap-3">
            <div className="hidden text-right leading-tight sm:block">
              <p className="text-sm font-medium text-slate-800">{session.fullName}</p>
              <p className="text-xs text-slate-500">{ROLE_LABEL[session.role]}</p>
            </div>
            <button
              onClick={() => void signOut()}
              className="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-sm text-slate-600 hover:bg-slate-100"
            >
              <LogOut className="size-4" />
              <span className="hidden sm:inline">Sign out</span>
            </button>
          </div>
        </header>
        <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-6 sm:px-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
