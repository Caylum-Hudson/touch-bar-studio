import test from 'node:test';
import assert from 'node:assert/strict';
import { isPointerWithinViewport } from './dragViewport.js';

const viewport = { left: 100, right: 900, top: 20, bottom: 80 };

test('pointer drops inside the visible custom area are accepted, including its edge', () => {
  assert.equal(isPointerWithinViewport({ x: 450, y: 50 }, viewport), true);
  assert.equal(isPointerWithinViewport({ x: 900, y: 80 }, viewport), true);
});

test('pointer drops over the reserved Control Strip lane are rejected', () => {
  assert.equal(isPointerWithinViewport({ x: 901, y: 50 }, viewport), false);
  assert.equal(isPointerWithinViewport({ x: 1050, y: 50 }, viewport), false);
});

test('missing pointer geometry stays compatible with non-pointer sensors', () => {
  assert.equal(isPointerWithinViewport(null, viewport), true);
  assert.equal(isPointerWithinViewport({ x: 450, y: 50 }, null), true);
});
