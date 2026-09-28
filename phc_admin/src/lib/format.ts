const TZ = 'Asia/Kolkata';

const dateFmt = new Intl.DateTimeFormat('en-IN', { day: '2-digit', month: 'short', year: 'numeric', timeZone: TZ });
const dateTimeFmt = new Intl.DateTimeFormat('en-IN', {
  day: '2-digit',
  month: 'short',
  hour: '2-digit',
  minute: '2-digit',
  timeZone: TZ,
});
const rtf = new Intl.RelativeTimeFormat('en-IN', { numeric: 'auto' });

export function formatDate(value: string | null | undefined): string {
  if (!value) return '—';
  // Plain YYYY-MM-DD dates are calendar dates — don't shift them through UTC.
  const d = /^\d{4}-\d{2}-\d{2}$/.test(value) ? new Date(`${value}T00:00:00+05:30`) : new Date(value);
  return Number.isNaN(d.getTime()) ? '—' : dateFmt.format(d);
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return '—';
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? '—' : dateTimeFmt.format(d);
}

export function formatRelative(value: string | null | undefined): string {
  if (!value) return 'Never';
  const diffMs = new Date(value).getTime() - Date.now();
  if (Number.isNaN(diffMs)) return '—';
  const mins = Math.round(diffMs / 60_000);
  if (Math.abs(mins) < 60) return rtf.format(mins, 'minute');
  const hours = Math.round(mins / 60);
  if (Math.abs(hours) < 24) return rtf.format(hours, 'hour');
  return rtf.format(Math.round(hours / 24), 'day');
}

/** Today's date in IST as YYYY-MM-DD (for <input type="date" min>). */
export function todayIST(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(new Date());
}

export function hoursSince(value: string | null | undefined): number {
  if (!value) return Infinity;
  return (Date.now() - new Date(value).getTime()) / 3_600_000;
}
