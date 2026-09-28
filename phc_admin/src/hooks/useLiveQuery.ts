import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { repository, type LiveTable } from '@/backend';
import { useSession } from '@/auth/AuthContext';

interface QueryState<T> {
  data: T | undefined;
  error: Error | null;
  loading: boolean;
  reload: () => void;
}

/**
 * Runs `fetcher(phcId)` for the logged-in PHC and re-runs it whenever one of
 * `liveTables` changes — whether the change came from this panel or from an
 * ASHA device syncing. Errors are surfaced, never swallowed into empty data.
 */
export function useLiveQuery<T>(
  fetcher: (phcId: string) => Promise<T>,
  liveTables: LiveTable[] = [],
): QueryState<T> {
  const { phcId } = useSession();
  const [data, setData] = useState<T>();
  const [error, setError] = useState<Error | null>(null);
  const [loading, setLoading] = useState(true);
  const [nonce, setNonce] = useState(0);

  // Keep the latest fetcher without re-subscribing every render.
  const fetcherRef = useRef(fetcher);
  useLayoutEffect(() => {
    fetcherRef.current = fetcher;
  });

  const reload = useCallback(() => setNonce((n) => n + 1), []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fetcherRef.current(phcId).then(
      (d) => {
        if (cancelled) return;
        setData(d);
        setError(null);
        setLoading(false);
      },
      (e: unknown) => {
        if (cancelled) return;
        setError(e instanceof Error ? e : new Error(String(e)));
        setLoading(false);
      },
    );
    return () => {
      cancelled = true;
    };
  }, [phcId, nonce]);

  const tablesKey = liveTables.join(',');
  useEffect(() => {
    if (!tablesKey) return;
    const offs = tablesKey.split(',').map((t) => repository.subscribe(phcId, t as LiveTable, reload));
    return () => offs.forEach((off) => off());
  }, [phcId, tablesKey, reload]);

  return { data, error, loading, reload };
}
