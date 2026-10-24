import {widgetContentWidth} from './widgetSizing.js';
import {SYSTEM_MONITOR_METRICS} from './systemMonitor.js';

export const BAR_WIDTH = 1085;
export const itemWidth = item => Math.max(24, Math.min(BAR_WIDTH, Number(item.width) || 64));
export const contentMinimumWidth = item => Math.min(BAR_WIDTH, widgetContentWidth(item) || 0);
export const contentFitWidth = item => Math.max(itemWidth(item), contentMinimumWidth(item));
export const clampPosition = (x, width) => Math.max(0, Math.min(BAR_WIDTH - width, Math.round(Number(x) || 0)));
export const isPrecise = items => items.some(item => Number.isFinite(item.studioPosition));
export function autoDockDisplayWidth(items, dockId, preferredWidth, visibleRightEdge = BAR_WIDTH) {
  const dock = items.find(item => item.id === dockId && item.type === 'dock');
  if (!dock || dock.autoResize === false || !Number.isFinite(preferredWidth)) return null;
  const x = clampPosition(Number.isFinite(dock.studioPosition) ? dock.studioPosition : 0, 0);
  const nextItemX = items
    .filter(item => item.id !== dockId && Number.isFinite(item.studioPosition) && item.studioPosition >= x)
    .reduce((nearest, item) => Math.min(nearest, item.studioPosition), Infinity);
  const edge = Math.max(0, Math.min(BAR_WIDTH, Number(visibleRightEdge) || 0));
  const neighborLimit = Number.isFinite(nextItemX) ? Math.max(0, nextItemX - x - 4) : Infinity;
  const preferredFrameWidth = preferredWidth + 14;
  return Math.max(0, Math.min(preferredFrameWidth, neighborLimit, edge - x));
}

export function fitDockIcons(frameWidth, count, iconSize = 32, itemSpacing = 1) {
  if (count <= 0) return {iconSize: 0, itemSpacing: 0};
  const available = Math.max(0, frameWidth - 14);
  const naturalStack = count * iconSize + (count - 1) * itemSpacing;
  const scale = naturalStack > 0 ? Math.min(1, available / naturalStack) : 0;
  return {iconSize: iconSize * scale, itemSpacing: itemSpacing * scale};
}

export function layoutFrames(items, {dockPreferredWidth, visibleRightEdge = BAR_WIDTH, contentScale = 1} = {}) {
  const scale = Number.isFinite(contentScale) && contentScale > 0 ? contentScale : 1;
  const dockWidth = Number.isFinite(dockPreferredWidth) ? (dockPreferredWidth + 14) / scale - 14 : dockPreferredWidth;
  const frames = new Map();
  for (const alignment of ['left', 'center', 'right']) {
    const group = items.filter(item => (item.align || 'center') === alignment);
    const widths = new Map(group.map(item => [item.id, item.type === 'dock'
      ? autoDockDisplayWidth(items, item.id, dockWidth, visibleRightEdge) ?? itemWidth(item)
      : item.type === 'systemMonitor' && item.autoFitContent
        ? Math.max(24, Math.ceil(contentMinimumWidth(item) / scale))
        : Math.max(itemWidth(item), Math.ceil(contentMinimumWidth(item) / scale))]));
    const total = group.reduce((sum, item) => sum + widths.get(item.id), 0) + Math.max(0, group.length - 1) * 4;
    let cursor = alignment === 'left' ? 0 : alignment === 'right' ? BAR_WIDTH - total : (BAR_WIDTH - total) / 2;
    for (const item of group) {
      const width = widths.get(item.id);
      frames.set(item.id, {x:Number.isFinite(item.studioPosition) ? item.studioPosition : clampPosition(cursor, width), width});
      cursor += width + 4;
    }
  }
  return frames;
}
export function overlappingItems(items, options) {
  const frames=layoutFrames(items, options);
  const ordered=items.map(item=>({item,...frames.get(item.id)})).sort((a,b)=>a.x-b.x);
  return ordered.some((a,i)=>a.x<0||a.x+a.width>BAR_WIDTH||ordered.slice(i+1).some(b=>b.x < a.x+a.width));
}

export const SNAP_DISTANCE = 10;
export const spacingGap = items => items.find(item => Number.isFinite(item.studioGap))?.studioGap ?? null;
const orderedFrames = (items, options) => {
  const frames = layoutFrames(items, options);
  return items.map(item => ({item, ...frames.get(item.id)})).sort((a,b) => a.x-b.x);
};

// Change each connected cluster's gap while keeping detached cluster anchors fixed.
export function setConsistentSpacing(items, gap) {
  gap = Math.max(0, Math.min(64, Math.round(Number(gap) || 0)));
  const previousGap = spacingGap(items);
  const ordered = orderedFrames(items);
  let previous = null;
  let cursor = 0;
  let lastEnd = -1;
  const positions = new Map();
  for (const frame of ordered) {
    const connected = previous && (previousGap === null || Math.abs(frame.x - previous.x - previous.width - previousGap) <= SNAP_DISTANCE);
    const x = connected ? cursor : frame.x;
    if (x < lastEnd) throw new Error('That gap would overlap another cluster. Move the clusters apart first.');
    if (x + frame.width > BAR_WIDTH) throw new Error('Not enough room for that gap. Reduce the gap or move a cluster left.');
    positions.set(frame.item.id, x);
    cursor = x + frame.width + gap;
    lastEnd = x + frame.width;
    previous = frame;
  }
  return items.map(item => ({...item, studioPosition:positions.get(item.id), studioGap:gap}));
}

// Every control can anchor a local grid. Outside the snap distance, placement stays free.
export function snapPosition(items, id, desiredX, width, gap = spacingGap(items), options) {
  const x = clampPosition(desiredX,width);
  if (gap === null) return {x,snapped:false};
  const neighbors = orderedFrames(items.filter(item => item.id !== id), options);
  const candidates = neighbors.flatMap(frame => [frame.x + frame.width + gap, frame.x - width - gap]);
  const possible = candidates.filter(candidate => candidate >= 0 && candidate+width <= BAR_WIDTH &&
    neighbors.every(frame => candidate+width <= frame.x || candidate >= frame.x+frame.width));
  const nearest = possible.sort((a,b) => Math.abs(a-x)-Math.abs(b-x))[0];
  return nearest !== undefined && Math.abs(nearest-x) <= SNAP_DISTANCE ? {x:nearest,snapped:true} : {x,snapped:false};
}

export function nextSpacedPosition(items, width, gap = spacingGap(items)) {
  if (gap === null) return null;
  const frames = orderedFrames(items);
  const candidates = [0, ...frames.map(frame => frame.x+frame.width+gap)];
  return candidates.find(x => x+width <= BAR_WIDTH && frames.every(frame => x+width+gap <= frame.x || x >= frame.x+frame.width+gap)) ?? null;
}

/** Place current controls across the custom region without shrinking their content.
 * The native runtime maps this logical region into the area beside the Control
 * Strip; the strip is not one of these items and must not be subtracted twice.
 */
export function distributeItemsEvenly(items, {availableWidth = BAR_WIDTH, dockPreferredWidth, contentScale = 1} = {}) {
  const width = Math.max(0, Math.min(BAR_WIDTH, Number(availableWidth) || 0));
  const scale = Number.isFinite(contentScale) && contentScale > 0 ? contentScale : 1;
  const ordered = orderedFrames(items);
  const widths = new Map(items.map(item => [item.id,
    item.type === 'dock' && item.autoResize !== false && Number.isFinite(dockPreferredWidth)
      ? Math.ceil((Math.max(0, dockPreferredWidth) + 14) / scale)
      : item.type === 'systemMonitor' && item.autoFitContent
        ? Math.max(24, Math.ceil(contentMinimumWidth(item) / scale))
        : Math.max(itemWidth(item), Math.ceil(contentMinimumWidth(item) / scale)),
  ]));
  const contentWidth = items.reduce((total, item) => total + widths.get(item.id), 0);
  const gap = items.length ? (width - contentWidth) / (items.length + 1) : 0;
  const dockNeedsGap = items.length > 1 && items.some(item => item.type === 'dock' && item.autoResize !== false);
  if (contentWidth > width || (dockNeedsGap && gap < 4)) {
    throw new Error('Not enough room to place all items evenly. Remove one or more items, then try again. Your layout has not changed.');
  }
  if (!items.length) return [];
  let cursor = gap;
  const positions = new Map();
  for (const {item} of ordered) {
    positions.set(item.id, Math.round(cursor));
    cursor += widths.get(item.id) + gap;
  }
  return items.map(item => {
    const next = {...item, studioPosition: positions.get(item.id)};
    // This is a one-time arrangement, independent of the local snapping grid.
    delete next.studioGap;
    return next;
  });
}

/** Copy only saved geometry out of transiently measured preview layouts. */
export function saveLayoutPositions(sourceItems, measuredItems, {clearGaps = false} = {}) {
  const measured = new Map(measuredItems.map(item => [item.id,item]));
  return sourceItems.map(item => {
    const next = {...item,studioPosition:measured.get(item.id)?.studioPosition};
    delete next.runtimePreview;
    if (clearGaps) delete next.studioGap;
    else if (measured.get(item.id)?.studioGap === undefined) delete next.studioGap;
    else next.studioGap = measured.get(item.id).studioGap;
    return next;
  });
}

/** Convert AppKit's base custom bounds into this editor level's logical scale. */
export function layoutContentScale(capacity, {submenu = false, resolveProfile = false} = {}) {
  if (!capacity || !Number.isFinite(capacity.physicalWidth) || capacity.physicalWidth <= 0) return null;
  const reserved = submenu ? 62 : resolveProfile ? 94 : 0;
  return capacity.physicalWidth / BAR_WIDTH * (BAR_WIDTH - reserved) / BAR_WIDTH;
}

const legacyMetricForType = {cpu:'cpu', gpuUsage:'gpu', ramUsage:'memory', cpuTemperature:'temperature'};

/** Combine metric controls in this bar into one undoable monitor item. */
export function combineLegacySystemMetrics(items, selectedId, options = {}) {
  const selected = items.find(item => item.id === selectedId);
  if (!selected || !legacyMetricForType[selected.type]) return null;
  const candidates = items.filter(item => legacyMetricForType[item.type] || item.type === 'systemMonitor');
  const metrics = SYSTEM_MONITOR_METRICS.filter(metric => candidates.some(item =>
    legacyMetricForType[item.type] === metric ||
    (item.type === 'systemMonitor' && (!Array.isArray(item.metrics) || item.metrics.includes(metric))),
  ));
  const frames = layoutFrames(items, options);
  const leftmost = Math.min(...candidates.map(item => frames.get(item.id)?.x ?? 0));
  const monitor = candidates.find(item => item.type === 'systemMonitor') || selected;
  const combined = {...monitor, type:'systemMonitor', metrics};
  delete combined.title;
  delete combined.image;
  const scale = Number.isFinite(options.contentScale) && options.contentScale > 0 ? options.contentScale : 1;
  const width = Math.max(24, Math.ceil((widgetContentWidth(combined) || 24) / scale));
  combined.width = width;
  combined.studioPosition = clampPosition(leftmost, width);
  const firstIndex = Math.min(...candidates.map(item => items.indexOf(item)));
  const result = items.filter(item => !candidates.includes(item));
  result.splice(firstIndex, 0, combined);
  return {items:result, selectedId:combined.id};
}
