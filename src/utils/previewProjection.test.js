import test from 'node:test';
import assert from 'node:assert/strict';
import {previewProjection, projectFrame, screenDeltaToLogical, screenXToLogical} from './previewProjection.js';

test('projects logical frames into native points and maps pointer movement back', () => {
  const projection = previewProjection(684, {availableWidth: 900});
  const frame = projectFrame({x: 100, width: 381}, projection);
  assert.equal(frame.width, 381 * 684 / 1085);
  assert.equal(screenXToLogical(frame.x * projection.fitScale, projection), 100);
  assert.equal(screenDeltaToLogical(50 * projection.baseScale * projection.childScale, projection), 50);
});

test('keeps native navigation reservations and logical coordinates aligned', () => {
  const projection = previewProjection(684, {reserved:62, availableWidth:900});
  const frame = projectFrame({x:100,width:381},projection);
  assert.equal(frame.x,(62+100*(1023/1085))*(684/1085));
  assert.equal(frame.width,381*(1023/1085)*(684/1085));
  assert.equal(screenXToLogical(frame.x*projection.fitScale,projection),100);
});

test('fits only when the preview viewport is narrower than native points', () => {
  assert.equal(previewProjection(684, {availableWidth: 700}).fitScale, 1);
  const narrow = previewProjection(684, {availableWidth: 342});
  assert.equal(narrow.fitScale, 0.5);
  const delta = 24 * narrow.baseScale * narrow.childScale * narrow.fitScale;
  assert.equal(screenDeltaToLogical(delta, narrow), 24);
});

test('includes the separate Control Strip and outer frame when fitting the whole preview', () => {
  const projection = previewProjection(760, {availableWidth: 600, extraWidth: 176 + 18});
  assert.equal(projection.projectedWidth, 954);
  assert.equal(projection.fitScale, 600 / 954);
});
