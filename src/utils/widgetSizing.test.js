import test from 'node:test';
import assert from 'node:assert/strict';
import {contentFitWidth,layoutFrames,overlappingItems} from './positionLayout.js';
import {estimateTouchBarTextWidth,formatTimePreview,widgetContentWidth} from './widgetSizing.js';
import {createElement} from '../data/elementDefinitions.js';

test('Date and CPU previews grow past their generic saved width without changing saved geometry', () => {
  const items = [
    {id:'date',type:'timeButton',formatTemplate:'MMM d',studioPosition:11,width:64},
    {id:'cpu',type:'cpu',studioPosition:201,width:64},
    {id:'dock',type:'dock',autoResize:true,studioPosition:520,width:200},
  ];
  const saved = structuredClone(items);
  const frames = layoutFrames(items);
  assert.ok(frames.get('date').width > 64);
  assert.ok(frames.get('cpu').width > 64);
  assert.deepEqual([...frames].map(([id,frame])=>[id,frame.x]),[['date',11],['cpu',201],['dock',520]]);
  assert.equal(overlappingItems(items),false);
  assert.deepEqual(items,saved);
});

test('system metric preview widths fit worst-case percentages and unavailable labels', () => {
  const cases = [
    [createElement('ramUsage'), 'RAM 100%'],
    [createElement('gpuUsage'), 'GPU 100%'],
    [createElement('boardTemperature'), 'Board —'],
  ];
  for (const [item, title] of cases) {
    const width = widgetContentWidth(item);
    const actualLabelWidth = Math.ceil(estimateTouchBarTextWidth(title) + 24);
    assert.ok(width >= actualLabelWidth, `${title} must fit with native control padding`);
    assert.ok(contentFitWidth({...item,studioPosition:0,width:24}) >= width);
  }
});

test('Date width accounts for the actual formatted preview and long common date formats', () => {
  const short={type:'timeButton',formatTemplate:'MMM d'};
  const long={type:'timeButton',formatTemplate:'EEEE, MMMM d, yyyy @ HH:mm'};
  assert.match(formatTimePreview(short.formatTemplate),/^\w{3} \d{1,2}$/);
  assert.ok(widgetContentWidth(long)>widgetContentWidth(short));
  assert.ok(contentFitWidth(long)>64);
});

test('tight content minimums trigger a placement warning instead of clipping silently', () => {
  const items=[
    {id:'date',type:'timeButton',formatTemplate:'EEEE, MMMM d, yyyy @ HH:mm',studioPosition:0,width:24},
    {id:'cpu',type:'cpu',studioPosition:90,width:24},
  ];
  assert.equal(overlappingItems(items),true);
  assert.ok(contentFitWidth(items[0])>items[0].width);
});

test('static button content fit includes the AppKit button chrome and keeps compact Resolve labels readable', () => {
  for (const title of ['Node ⏻','All ⏻','← Node','Node →']) {
    assert.equal(widgetContentWidth({type:'staticButton',title}),Math.ceil(estimateTouchBarTextWidth(title)+24));
  }
  assert.ok(widgetContentWidth({type:'staticButton',title:'Node ⏻'})>64);
});
