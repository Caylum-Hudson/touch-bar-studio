import { parseJSON } from './jsonGenerator.js';
import { resolveNumericBindingError } from './resolveNumericDial.js';

const resolvePages = new Set(['media', 'photo', 'cut', 'edit', 'fusion', 'color', 'fairlight', 'deliver']);
const isRecord = value => value !== null && typeof value === 'object' && !Array.isArray(value);

function validateItems(items, label) {
  if (!Array.isArray(items)) return `${label} must be an array of controls.`;
  const result = parseJSON(JSON.stringify(items));
  if (result.error) return `${label}: ${result.error}`;
  const validateNumeric = (controls, path) => {
    for (const item of controls) {
      if (item.type === 'resolveNumericDial') {
        if (item.step !== undefined && (!Number.isFinite(item.step) || item.step < 0.0001 || item.step > 1)) return `${path}: Resolve Adjustment Dial step must be between 0.0001 and 1.`;
        const bindingError = resolveNumericBindingError(item.binding);
        if (bindingError) return `${path}: ${bindingError}`;
      }
      if (item.type === 'group' && item.items) {
        const nestedError = validateNumeric(item.items, path);
        if (nestedError) return nestedError;
      }
    }
    return null;
  };
  return validateNumeric(result.items, label);
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
  const markRetainedStudioIds = items => items.map(item => ({
    ...item,
    ...(item.studioId != null ? {preserveStudioId:true} : {}),
    ...(Array.isArray(item.items) ? {items:markRetainedStudioIds(item.items)} : {}),
  }));
  return Object.fromEntries(Object.entries(workspace.profiles).map(([id, profile]) => {
    const parsedItems = parseJSON(JSON.stringify(profile.items));
    const items = {...parsedItems, items:markRetainedStudioIds(parsedItems.items)};
    const resolvePageLayouts = profile.resolvePageLayouts
      ? Object.fromEntries(Object.entries(profile.resolvePageLayouts).map(([page, pageItems]) => {
          const parsedPageItems = parseJSON(JSON.stringify(pageItems));
          return [page, markRetainedStudioIds(parsedPageItems.items)];
        }))
      : undefined;
    return [id, {
      ...profile,
      items: items.items,
      ...(resolvePageLayouts ? { resolvePageLayouts } : {}),
    }];
  }));
}
