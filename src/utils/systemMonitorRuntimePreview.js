import { selectedSystemMonitorMetrics } from './systemMonitor.js';

const stableImageIdentity = image => {
  if (!image) return null;
  if (typeof image === 'string') return image;
  return { filePath:image.filePath || null, base64:image.base64 || null, data:image.data || null };
};

export function systemMonitorConfigurationSignature(item = {}) {
  const content = JSON.stringify({
    metrics:selectedSystemMonitorMetrics(item),
    title:item.title || '',
    image:stableImageIdentity(item.image),
    bordered:item.bordered !== false,
    background:item.background || null,
    autoFitContent:item.autoFitContent === true,
  });
  let hash = 2166136261;
  for (let i = 0; i < content.length; i += 1) {
    hash ^= content.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

// Restoring a saved workspace regenerates editor IDs but retains native studio IDs.
const matchesRuntimeId = (item, runtimeId) => typeof runtimeId === 'string' && runtimeId.length > 0
  && (item.id === runtimeId || item.studioId === runtimeId);

function currentItemsForContext({ profiles, profileId, resolvePageId, groupPath, activeGroupPath }) {
  const profile = profiles?.[profileId];
  if (!profile) return null;
  let items = profile.items || [];
  if (profile.bundleId === 'com.blackmagic-design.DaVinciResolve' && resolvePageId && resolvePageId !== 'fallback') {
    if (!profile.resolvePageLayouts || !Object.prototype.hasOwnProperty.call(profile.resolvePageLayouts, resolvePageId)) return null;
    items = profile.resolvePageLayouts[resolvePageId];
  }
  if (groupPath.length !== activeGroupPath.length) return null;
  for (const [index,groupId] of groupPath.entries()) {
    const group = items.find(item => item.id === groupId && item.type === 'group');
    const matchingGroups = items.filter(item => item.type === 'group' && matchesRuntimeId(item,activeGroupPath[index]));
    if (!group || matchingGroups.length !== 1 || matchingGroups[0] !== group) return null;
    items = group.items || [];
  }
  return items;
}

export function matchSystemMonitorRuntimePreviews({ rows = [], profiles, profileId, resolvePageId = null, groupPath = [], activeProfile = null, activeResolvePage = null, activeGroupPath = [], runtimeEnabled = false }) {
  if (!runtimeEnabled) return new Map();
  const profile = profiles?.[profileId];
  const editedPage = profile?.bundleId === 'com.blackmagic-design.DaVinciResolve' && resolvePageId !== 'fallback' ? resolvePageId : null;
  const runtimePage = activeResolvePage === 'fallback' ? null : activeResolvePage;
  if (activeProfile !== profileId || editedPage !== runtimePage) return new Map();
  const items = currentItemsForContext({ profiles, profileId, resolvePageId, groupPath, activeGroupPath });
  if (!items) return new Map();
  const scan = items;
  return new Map(rows.flatMap(row => {
    const candidates = scan.filter(candidate => candidate.type === 'systemMonitor' && matchesRuntimeId(candidate,row.studioId));
    const item = candidates.length === 1 ? candidates[0] : null;
    if (!item || !item.autoFitContent) return [];
    if (JSON.stringify(selectedSystemMonitorMetrics(item)) !== JSON.stringify(row.metrics || [])) return [];
    if (systemMonitorConfigurationSignature(item) !== row.signature) return [];
    if (!Number.isFinite(row.naturalWidth) || row.naturalWidth <= 0 || typeof row.title !== 'string') return [];
    return [[item.id, {title:row.title, contentWidth:row.naturalWidth, frameWidth:row.frameWidth}]];
  }));
}
