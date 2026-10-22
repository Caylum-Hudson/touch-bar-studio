import test from 'node:test';
import assert from 'node:assert/strict';
import {autoDockDisplayWidth, fitDockIcons, layoutFrames, distributeItemsEvenly, layoutContentScale} from './positionLayout.js';

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


test('even placement preserves visual order, sizes and source data with equal outer gaps', () => {
  const items = [
    {id:'right',type:'volume',width:100,studioPosition:500,studioGap:12},
    {id:'left',type:'volume',width:50,studioPosition:100,studioGap:12},
  ];
  const before = structuredClone(items);
  const result = distributeItemsEvenly(items,{availableWidth:300});
  assert.equal(result[1].studioPosition,50);
  assert.equal(result[0].studioPosition,150);
  assert.deepEqual(result.map(item=>item.width),[100,50]);
  assert.ok(result.every(item=>item.studioGap === undefined));
  assert.deepEqual(items,before);
});

test('no-fit placement explicitly asks for removal and never changes the source layout', () => {
  const items = [{id:'a',type:'volume',width:200,studioPosition:9},{id:'b',type:'volume',width:200,studioPosition:260}];
  const before = structuredClone(items);
  assert.throws(()=>distributeItemsEvenly(items,{availableWidth:399}),/Remove one or more items/);
  assert.deepEqual(items,before);
});

test('placement stays inside an explicit usable region beside reserved right-side space', () => {
  const items = [{id:'a',type:'volume',width:100},{id:'b',type:'volume',width:100}];
  const result = distributeItemsEvenly(items,{availableWidth:800});
  assert.equal(result[0].studioPosition,200);
  assert.equal(result[1].studioPosition,500);
  assert.ok(result.every(item=>item.studioPosition+item.width<=800));
});

test('content widths and natural Dock width are checked without shrinking to force a fit', () => {
  const dock = {id:'dock',type:'dock',autoResize:true,width:50,studioPosition:0};
  const metric = {id:'cpu',type:'cpu',width:24,studioPosition:1};
  assert.throws(()=>distributeItemsEvenly([dock,metric],{availableWidth:300,dockPreferredWidth:250}),/Not enough room/);
  assert.throws(()=>distributeItemsEvenly([metric],{availableWidth:30}),/Not enough room/);
  const fixed = {...dock,autoResize:false,width:50};
  assert.doesNotThrow(()=>distributeItemsEvenly([fixed],{availableWidth:100,dockPreferredWidth:250}));
});

test('single control is centred and empty placement is safe', () => {
  assert.equal(distributeItemsEvenly([{id:'a',type:'volume',width:100}],{availableWidth:300})[0].studioPosition,100);
  assert.deepEqual(distributeItemsEvenly([]),[]);
});


test('native content minima widen in logical units without changing configured widths', () => {
  const item = {id:'cpu',type:'cpu',width:24};
  assert.doesNotThrow(()=>distributeItemsEvenly([item],{availableWidth:150}));
  assert.throws(()=>distributeItemsEvenly([item],{availableWidth:150,contentScale:0.5}),/Remove/);
  const result = distributeItemsEvenly([item],{contentScale:0.5});
  assert.equal(result[0].width,24);
});

test('capacity uses native bounds, counts the right strip once, and reserves editor-level controls', () => {
  const capacity = {physicalWidth:760,logicalWidth:1085,keepControlStrip:true};
  assert.equal(layoutContentScale(capacity),760/1085);
  assert.equal(layoutContentScale(capacity,{submenu:true,resolveProfile:true}),760/1085*1023/1085);
  assert.equal(layoutContentScale(capacity,{resolveProfile:true}),760/1085*991/1085);
  assert.equal(layoutContentScale(null),null);
});


test('native Dock neighbour clearance is retained instead of silently shrinking icons', () => {
  const items=[{id:'dock',type:'dock',autoResize:true,width:100},{id:'button',type:'volume',width:100}];
  assert.throws(()=>distributeItemsEvenly(items,{availableWidth:205,dockPreferredWidth:86}),/Remove/);
});
