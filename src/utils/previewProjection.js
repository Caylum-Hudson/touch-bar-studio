import { BAR_WIDTH } from './positionLayout.js';

/** Map saved logical bar coordinates into the points used by the native preview. */
export function previewProjection(physicalWidth, {reserved = 0, availableWidth = physicalWidth, extraWidth = 0, calibration = 1} = {}) {
  const width = Number.isFinite(physicalWidth) && physicalWidth > 0 ? physicalWidth : BAR_WIDTH;
  const baseScale = width / BAR_WIDTH;
  const childScale = (BAR_WIDTH - reserved) / BAR_WIDTH;
  const projectedWidth = width + Math.max(0, Number(extraWidth) || 0);
  const requestedScale = Number.isFinite(calibration) ? Math.min(1, Math.max(0.5, calibration)) : 1;
  // Calibration is a percentage of available width, capped to keep the
  // preview inside its editor viewport.
  const fitScale = Number.isFinite(availableWidth) && availableWidth > 0
    ? availableWidth / projectedWidth * requestedScale
    : requestedScale;
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
