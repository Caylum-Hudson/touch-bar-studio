import { controlCatalog, advancedControlCatalog } from './controlCatalog.js';

export const controlPacks = [...controlCatalog, ...advancedControlCatalog];
export const defaultControlPackPreferences = {
  installed: controlPacks.map(({ id }) => id),
  hidden: [],
  favorites: [],
};

export function normalizeControlPackPreferences(value) {
  const validIds = new Set(controlPacks.map(({ id }) => id));
  const validKeys = new Set(controlPacks.flatMap(({ controls }) => controls.map(({ key }) => key)));
  const list = (candidate, valid) => Array.isArray(candidate)
    ? [...new Set(candidate.filter((item) => valid.has(item)))]
    : [];
  // Older installations had one flat library. Treat missing preferences as that
  // complete library so an upgrade never hides controls from existing users.
  return {
    installed: value && Array.isArray(value.installed)
      ? list(value.installed, validIds)
      : [...defaultControlPackPreferences.installed],
    hidden: list(value?.hidden, validIds),
    favorites: list(value?.favorites, validKeys),
    addedAt: Object.fromEntries(Object.entries(value?.addedAt || {}).filter(([id, timestamp]) => validIds.has(id) && Number.isFinite(timestamp))),
  };
}

export function visibleControlPacks(preferences) {
  const normalized = normalizeControlPackPreferences(preferences);
  return controlPacks.filter((pack) => normalized.installed.includes(pack.id)
    && !normalized.hidden.includes(pack.id));
}

export function hiddenControlPacks(preferences) {
  const normalized = normalizeControlPackPreferences(preferences);
  return controlPacks.filter((pack) => normalized.installed.includes(pack.id)
    && normalized.hidden.includes(pack.id));
}
