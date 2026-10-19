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
