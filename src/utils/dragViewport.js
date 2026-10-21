/** Preserve keyboard drags and reject pointer drops beyond the visible Touch Bar viewport. */
export function isPointerWithinViewport(pointer, viewport) {
  if (!pointer || !viewport) return true;
  return pointer.x >= viewport.left && pointer.x <= viewport.right &&
    pointer.y >= viewport.top && pointer.y <= viewport.bottom;
}
