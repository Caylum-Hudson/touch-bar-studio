export const BAR_WIDTH = 1085;
export const itemWidth = item => Math.max(24, Math.min(BAR_WIDTH, Number(item.width) || 64));
export const clampPosition = (x, width) => Math.max(0, Math.min(BAR_WIDTH - width, Math.round(Number(x) || 0)));
export const isPrecise = items => items.some(item => Number.isFinite(item.studioPosition));
export function layoutFrames(items) {
  const frames = new Map();
  for (const alignment of ['left', 'center', 'right']) {
    const group = items.filter(item => (item.align || 'center') === alignment);
    const total = group.reduce((sum, item) => sum + itemWidth(item), 0) + Math.max(0, group.length - 1) * 4;
    let cursor = alignment === 'left' ? 0 : alignment === 'right' ? BAR_WIDTH - total : (BAR_WIDTH - total) / 2;
    for (const item of group) {
      const width = itemWidth(item);
      frames.set(item.id, {x:clampPosition(Number.isFinite(item.studioPosition) ? item.studioPosition : cursor, width), width});
      cursor += width + 4;
    }
  }
  return frames;
}
export function overlappingItems(items) {
  const frames=layoutFrames(items);
  const ordered=items.map(item=>({item,...frames.get(item.id)})).sort((a,b)=>a.x-b.x);
  return ordered.some((a,i)=>ordered.slice(i+1).some(b=>b.x < a.x+a.width));
}

export const SNAP_DISTANCE = 10;
export const spacingGap = items => items.find(item => Number.isFinite(item.studioGap))?.studioGap ?? null;
const orderedFrames = items => {
  const frames = layoutFrames(items);
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
  return items.map(item => ({...item, studioPosition:positions.get(item.id), width:itemWidth(item), studioGap:gap}));
}

// Every control can anchor a local grid. Outside the snap distance, placement stays free.
export function snapPosition(items, id, desiredX, width, gap = spacingGap(items)) {
  const x = clampPosition(desiredX,width);
  if (gap === null) return {x,snapped:false};
  const neighbors = orderedFrames(items.filter(item => item.id !== id));
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
