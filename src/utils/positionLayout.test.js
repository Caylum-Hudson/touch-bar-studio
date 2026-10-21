import test from 'node:test';
import assert from 'node:assert/strict';
import {autoDockDisplayWidth, fitDockIcons, layoutFrames} from './positionLayout.js';

test('auto Dock preview fits its live width before the next control', () => {
  const items = [
    {id: 'dock', type: 'dock', autoResize: true, studioPosition: 465, width: 200},
    {id: 'exit', type: 'exitTouchbar', studioPosition: 650, width: 36},
  ];
  const frames = layoutFrames(items, {dockPreferredWidth: 420, visibleRightEdge: 900});
  assert.deepEqual(frames.get('dock'), {x: 465, width: 181});
  assert.deepEqual(frames.get('exit'), {x: 650, width: 36});
  assert.equal(autoDockDisplayWidth(items, 'dock', 420, 900), 181);
});

test('auto Dock preview shrinks to the visible ruler edge and handles an offscreen item', () => {
  const items = [{id: 'dock', type: 'dock', autoResize: true, studioPosition: 465, width: 200}];
  assert.equal(autoDockDisplayWidth(items, 'dock', 500, 720), 255);
  assert.equal(autoDockDisplayWidth(items, 'dock', 500, 400), 0);
});

test('auto Dock sizing does not mutate saved position or width', () => {
  const dock = {id: 'dock', type: 'dock', autoResize: true, studioPosition: 465, width: 200};
  const items = [dock];
  const before = structuredClone(items);
  const frames = layoutFrames(items, {dockPreferredWidth: 400, visibleRightEdge: 800});
  assert.equal(frames.get('dock').width, 335);
  assert.deepEqual(items, before);
});

test('native preferred width is icon-stack width plus the preview tile chrome', () => {
  const items = [{id: 'dock', type: 'dock', autoResize: true, studioPosition: 200, width: 200}];
  assert.equal(autoDockDisplayWidth(items, 'dock', 165, 900), 179);
});

test('Dock icons and gaps shrink together when the slot is tight', () => {
  const fit = fitDockIcons(80, 5, 32, 1);
  assert.ok(5 * fit.iconSize + 4 * fit.itemSpacing <= 66);
  assert.ok(fit.itemSpacing < 1);
});

test('Dock icons and gaps collapse safely when no room remains', () => {
  assert.deepEqual(fitDockIcons(0, 5, 32, 1), {iconSize: 0, itemSpacing: 0});
});
