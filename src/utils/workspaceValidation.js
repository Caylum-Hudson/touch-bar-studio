import { parseJSON } from './jsonGenerator.js';

const resolvePages = new Set(['media', 'photo', 'cut', 'edit', 'fusion', 'color', 'fairlight', 'deliver']);
const isRecord = value => value !== null && typeof value === 'object' && !Array.isArray(value);

function validateItems(items, label) {
  if (!Array.isArray(items)) return `${label} must be an array of controls.`;
  const result = parseJSON(JSON.stringify(items));
  return result.error ? `${label}: ${result.error}` : null;
}

/** Validate all profile and Resolve layouts before they enter editor state. */
export function workspaceImportError(workspace) {
  if (!isRecord(workspace) || workspace.version !== 1 || !isRecord(workspace.profiles) || !isRecord(workspace.profiles.default)) {
    return 'Expected a version 1 workspace with a Default profile.';
  }

  const bundleIdentifiers = new Set();
  for (const [id, profile] of Object.entries(workspace.profiles)) {
    if (!isRecord(profile)) return `Profile ${id} must be an object.`;
    if (id !== 'default' && profile.enabled !== false && (typeof profile.bundleId !== 'string' || !profile.bundleId.trim())) {
      return `Enabled app profile ${id} needs a bundle identifier.`;
    }
    if (id !== 'default' && profile.enabled !== false) {
      if (bundleIdentifiers.has(profile.bundleId)) return `Enabled app profiles cannot share bundle identifier ${profile.bundleId}.`;
      bundleIdentifiers.add(profile.bundleId);
    }
    const itemError = validateItems(profile.items, `Profile ${id}`);
    if (itemError) return itemError;

    if (profile.resolvePageLayouts !== undefined) {
      if (!isRecord(profile.resolvePageLayouts)) return `Resolve page layouts in profile ${id} must be an object.`;
      for (const [page, items] of Object.entries(profile.resolvePageLayouts)) {
        if (!resolvePages.has(page)) return `Resolve page ${page} is not recognized.`;
        const pageError = validateItems(items, `Resolve ${page} layout in profile ${id}`);
        if (pageError) return pageError;
      }
    }
  }
  return null;
}

/** Convert only fully validated imported layouts to editor control state. */
export function restoreWorkspaceProfiles(workspace) {
  if (workspaceImportError(workspace)) return null;
  return Object.fromEntries(Object.entries(workspace.profiles).map(([id, profile]) => {
    const items = parseJSON(JSON.stringify(profile.items));
    const resolvePageLayouts = profile.resolvePageLayouts
      ? Object.fromEntries(Object.entries(profile.resolvePageLayouts).map(([page, pageItems]) => [page, parseJSON(JSON.stringify(pageItems)).items]))
      : undefined;
    return [id, {
      ...profile,
      items: items.items,
      ...(resolvePageLayouts ? { resolvePageLayouts } : {}),
    }];
  }));
}
