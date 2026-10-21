import {useEffect, useState} from 'react';

export function useDockPreview(filter) {
  const [snapshot, setSnapshot] = useState({revision: null, filter: undefined, apps: [], preferredWidth: null, iconSize: 32, itemSpacing: 1});
  useEffect(() => {
    let stopped = false;
    let timer;
    const refresh = async () => {
      try {
        const params = new URLSearchParams();
        if (snapshot.revision !== null && snapshot.filter === filter) params.set('sinceRevision', snapshot.revision);
        if (filter !== undefined) params.set('filter', filter);
        const query = params.size ? `?${params}` : '';
        const response = await fetch(`/api/dock-preview${query}`);
        if (response.ok) {
          const next = await response.json();
          if (!stopped && next.success && !next.unchanged && Array.isArray(next.apps)) {
            setSnapshot({
              revision: next.revision,
              filter,
              apps: next.apps,
              preferredWidth: Number(next.preferredWidth),
              iconSize: Number(next.iconSize) || 32,
              itemSpacing: Number.isFinite(Number(next.itemSpacing)) ? Number(next.itemSpacing) : 1,
            });
          }
        }
      } catch { /* The preview remains empty when MTMR is unavailable. */ }
      if (!stopped) timer = setTimeout(refresh, 2000);
    };
    refresh();
    return () => { stopped = true; clearTimeout(timer); };
  }, [filter, snapshot.revision, snapshot.filter]);
  return snapshot;
}
