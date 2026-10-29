import test from 'node:test';
import assert from 'node:assert/strict';
import {previewProjection, projectFrame, screenDeltaToLogical, screenXToLogical} from './previewProjection.js';

test('projects logical frames into native points and maps pointer movement back', () => {
  const projection = previewProjection(684, {availableWidth: 900});
  const frame = projectFrame({x: 100, width: 381}, projection);
  assert.equal(frame.width, 381 * 684 / 1085);
  assert.equal(screenXToLogical(frame.x * projection.fitScale, projection), 100);
  assert.ok(Math.abs(screenDeltaToLogical(50 * projection.baseScale * projection.childScale * projection.fitScale, projection) - 50) < 1e-9);
});

test('keeps native navigation reservations and logical coordinates aligned', () => {
  const projection = previewProjection(684, {reserved:62, availableWidth:900});
  const frame = projectFrame({x:100,width:381},projection);
  assert.equal(frame.x,(62+100*(1023/1085))*(684/1085));
  assert.equal(frame.width,381*(1023/1085)*(684/1085));
  assert.equal(screenXToLogical(frame.x*projection.fitScale,projection),100);
});

test('fills the selected share of available width, including in a narrow editor', () => {
  assert.equal(previewProjection(684, {availableWidth: 700}).fitScale, 700 / 684);
  const narrow = previewProjection(684, {availableWidth: 342});
  assert.equal(narrow.fitScale, 342 / 684);
  const delta = 24 * narrow.baseScale * narrow.childScale * narrow.fitScale;
  assert.equal(screenDeltaToLogical(delta, narrow), 24);
});

test('includes the separate Control Strip and outer frame when fitting the whole preview', () => {
  const projection = previewProjection(760, {availableWidth: 600, extraWidth: 176 + 2});
  assert.equal(projection.projectedWidth, 938);
  assert.equal(projection.fitScale, 600 / 938);
});

test('scales the native preview to the full width in a wide or fullscreen editor', () => {
  const projection = previewProjection(1085, {availableWidth: 4000, calibration: 1});
  assert.equal(projection.fitScale, 4000 / 1085);
  assert.equal(projection.displayWidth, 4000);
});

test('caps preview width at the viewport and preserves pointer mapping', () => {
  const projection = previewProjection(1085, {availableWidth: 4000, calibration: 1.5});
  assert.equal(projection.fitScale, 4000 / 1085);
  assert.equal(screenXToLogical(300 * projection.baseScale * projection.fitScale, projection), 300);
  assert.equal(screenDeltaToLogical(12 * projection.baseScale * projection.fitScale, projection), 12);
});

test('caps preview width when requested width exceeds the viewport', () => {
  const projection = previewProjection(1085, {availableWidth: 800, calibration: 1.5});
  assert.equal(projection.fitScale, 800 / 1085);
  assert.ok(Math.abs(screenXToLogical(250 * projection.baseScale * projection.fitScale, projection) - 250) < 1e-9);
});

test('clamps preview width to the supported 50 to 100 percent range', () => {
  assert.equal(previewProjection(1085, {availableWidth: 4000, calibration: 0.1}).fitScale, 0.5 * 4000 / 1085);
  assert.equal(previewProjection(1085, {availableWidth: 4000, calibration: 3}).fitScale, 4000 / 1085);
});
