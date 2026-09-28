import { useState, type FormEvent } from 'react';
import { repository, type VisitTask } from '@/backend';
import { useSession } from '@/auth/AuthContext';
import { useLiveQuery } from '@/hooks/useLiveQuery';
import { Badge, Button, Card, CardHeader, EmptyState, InlineError, PageHeader, QueryView } from '@/components/ui';
import { formatDate, formatRelative, todayIST } from '@/lib/format';

const STATUS_TONE = { pending: 'amber', done: 'green', cancelled: 'neutral' } as const;

export function TasksPage() {
  const tasks = useLiveQuery((phc) => repository.listTasks(phc), ['visit_tasks']);

  return (
    <>
      <PageHeader title="Visit tasks" subtitle="Assign follow-ups to ASHA workers. Their app downloads these on next sync." />
      <div className="grid gap-6 lg:grid-cols-[22rem_1fr]">
        <NewTaskForm />
        <Card>
          <CardHeader title="Assigned tasks" />
          <QueryView query={tasks} isEmpty={(d) => d.length === 0} empty={<EmptyState title="No tasks assigned yet" />}>
            {(list) => (
              <ul className="divide-y divide-slate-100">
                {list.map((t) => (
                  <TaskRow key={t.id} task={t} />
                ))}
              </ul>
            )}
          </QueryView>
        </Card>
      </div>
    </>
  );
}

function TaskRow({ task }: { task: VisitTask }) {
  const { phcId } = useSession();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function cancel() {
    if (!window.confirm(`Cancel "${task.title}" for ${task.ashaName ?? 'this worker'}?`)) return;
    setBusy(true);
    setError(null);
    try {
      await repository.cancelTask(phcId, task.id);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Cancel failed.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <li className="px-4 py-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <p className="text-sm font-medium text-slate-800">{task.title}</p>
            <Badge tone={STATUS_TONE[task.status]}>{task.status}</Badge>
          </div>
          <p className="text-xs text-slate-500">
            {task.ashaName ?? '—'}
            {task.memberName && <> · {task.memberName}</>} · Due {formatDate(task.dueDate)} · Created {formatRelative(task.createdAt)}
          </p>
          {task.notes && <p className="mt-1 text-xs text-slate-600">{task.notes}</p>}
        </div>
        {task.status === 'pending' && (
          <Button variant="danger" loading={busy} onClick={() => void cancel()} className="shrink-0 px-2.5 py-1.5 text-xs">
            Cancel
          </Button>
        )}
      </div>
      {error && (
        <div className="mt-2">
          <InlineError message={error} />
        </div>
      )}
    </li>
  );
}

function NewTaskForm() {
  const { phcId } = useSession();
  const workers = useLiveQuery((phc) => repository.listWorkers(phc));
  const [ashaId, setAshaId] = useState('');
  const [title, setTitle] = useState('');
  const [notes, setNotes] = useState('');
  const [dueDate, setDueDate] = useState(todayIST());
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSaved(false);
    if (!ashaId || !title.trim() || !dueDate) {
      setError('Choose a worker, enter a title and a due date.');
      return;
    }
    setSaving(true);
    try {
      await repository.createTask(phcId, { ashaId, title: title.trim(), notes: notes.trim() || undefined, dueDate });
      setTitle('');
      setNotes('');
      setSaved(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not create task.');
    } finally {
      setSaving(false);
    }
  }

  const input = 'w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm outline-none focus:border-brand-600';

  return (
    <Card className="h-fit">
      <CardHeader title="New task" />
      <form onSubmit={onSubmit} className="space-y-3 p-4">
        <label className="block">
          <span className="mb-1 block text-sm font-medium text-slate-700">ASHA worker</span>
          <select value={ashaId} onChange={(e) => setAshaId(e.target.value)} className={input} disabled={!workers.data}>
            <option value="">{workers.error ? 'Could not load workers' : workers.data ? 'Select…' : 'Loading…'}</option>
            {workers.data
              ?.filter((w) => w.isActive)
              .map((w) => (
                <option key={w.id} value={w.id}>
                  {w.fullName}
                </option>
              ))}
          </select>
        </label>
        <label className="block">
          <span className="mb-1 block text-sm font-medium text-slate-700">Title</span>
          <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. ANC visit — check BP" className={input} />
        </label>
        <label className="block">
          <span className="mb-1 block text-sm font-medium text-slate-700">Due date</span>
          <input type="date" min={todayIST()} value={dueDate} onChange={(e) => setDueDate(e.target.value)} className={input} />
        </label>
        <label className="block">
          <span className="mb-1 block text-sm font-medium text-slate-700">Notes (optional)</span>
          <textarea rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} className={input} />
        </label>
        <InlineError message={error} />
        {saved && <p className="text-sm text-emerald-700">Task assigned.</p>}
        <Button type="submit" loading={saving} className="w-full">
          Assign task
        </Button>
      </form>
    </Card>
  );
}
