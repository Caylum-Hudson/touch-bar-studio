import { BAR_WIDTH } from './positionLayout.js';

/** Map saved logical bar coordinates into the points used by the native preview. */
export function previewProjection(physicalWidth, {reserved = 0, availableWidth = physicalWidth, extraWidth = 0} = {}) {
  const width = Number.isFinite(physicalWidth) && physicalWidth > 0 ? physicalWidth : BAR_WIDTH;
  const baseScale = width / BAR_WIDTH;
  const childScale = (BAR_WIDTH - reserved) / BAR_WIDTH;
  const projectedWidth = width + Math.max(0, Number(extraWidth) || 0);
  const fitScale = Number.isFinite(availableWidth) && availableWidth > 0
    ? Math.min(1, availableWidth / projectedWidth)
    : 1;
  return {width, reserved, baseScale, childScale, fitScale, projectedWidth, displayWidth: projectedWidth * fitScale};
}

export function projectFrame(frame, projection) {
  const {reserved, baseScale, childScale} = projection;
  return {
    x: (reserved + frame.x * childScale) * baseScale,
    width: frame.width * childScale * baseScale,
  };
}

export function screenDeltaToLogical(delta, projection) {
  return delta / (projection.baseScale * projection.childScale * projection.fitScale);
}

export function screenXToLogical(x, projection) {
  return (x / projection.fitScale / projection.baseScale - projection.reserved) / projection.childScale;
}
