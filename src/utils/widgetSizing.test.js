import test from 'node:test';
import assert from 'node:assert/strict';
import {contentFitWidth,layoutFrames,overlappingItems} from './positionLayout.js';
import {estimateTouchBarTextWidth,formatTimePreview,longestDateText,widgetContentWidth,systemMonitorWidthForSelection,widgetWidthForContent} from './widgetSizing.js';
import {createElement} from '../data/elementDefinitions.js';
import {systemMonitorPreview, selectedSystemMonitorMetrics} from './systemMonitor.js';

test('Date and CPU previews grow past their generic saved width without changing saved geometry', () => {
  const items = [
    {id:'date',type:'timeButton',formatTemplate:'EEEE, MMMM d, yyyy @ HH:mm',studioPosition:11,width:64},
    {id:'cpu',type:'cpu',studioPosition:350,width:64},
    {id:'dock',type:'dock',autoResize:true,studioPosition:520,width:200},
  ];
  const saved = structuredClone(items);
  const frames = layoutFrames(items);
  assert.ok(frames.get('date').width > 64);
  assert.ok(frames.get('cpu').width > 64);
  assert.deepEqual([...frames].map(([id,frame])=>[id,frame.x]),[['date',11],['cpu',350],['dock',520]]);
  assert.equal(overlappingItems(items),false);
  assert.deepEqual(items,saved);
});

test('system metric preview widths fit worst-case percentages and unavailable labels', () => {
  const cases = [
    [createElement('cpu'), '100%'],
    [createElement('ramUsage'), '100%'],
    [createElement('gpuUsage'), '100%'],
    [createElement('cpuTemperature'), '130°C'],
  ];
  for (const [item, title] of cases) {
    const width = widgetContentWidth(item);
    const actualLabelWidth = Math.ceil(estimateTouchBarTextWidth(title) + 52);
    assert.ok(width >= actualLabelWidth, `${title} must fit with an 18px icon, 4px gap, 20px padding, and font allowance`);
    assert.ok(contentFitWidth({...item,studioPosition:0,width:24}) >= width);
  }
});

test('System Monitor previews selected readings in a fixed order with compact icon and padding allowance', () => {
  const monitor=createElement('systemMonitor');
  assert.deepEqual(selectedSystemMonitorMetrics(monitor),['cpu','gpu','memory','temperature']);
  assert.deepEqual(systemMonitorPreview(monitor),['100%','100%','100%','130°C']);
  assert.ok(widgetContentWidth(monitor) > widgetContentWidth({...monitor,metrics:['cpu']}));
  assert.deepEqual(systemMonitorPreview({...monitor,metrics:['temperature','memory']}),['100%','130°C']);
  assert.equal(widgetContentWidth({...monitor,metrics:[]}),42);
  assert.equal(widgetContentWidth(monitor),Math.ceil(estimateTouchBarTextWidth('100% · 100% · 100% · 130°C')+49));
});

test('System Monitor selection width shrinks to icon-only and grows for selected values at native scale', () => {
  const icon=systemMonitorWidthForSelection([]);
  const gpu=systemMonitorWidthForSelection(['gpu']);
  const all=systemMonitorWidthForSelection(['cpu','gpu','memory','temperature']);
  assert.equal(icon,42);
  assert.ok(gpu>icon);
  assert.ok(all>gpu);
  assert.equal(systemMonitorWidthForSelection([],0.7),Math.ceil(widgetContentWidth({type:'systemMonitor',metrics:[]})/0.7));
});

test('Date width accounts for the actual formatted preview and long common date formats', () => {
  const short={type:'timeButton',formatTemplate:'MMM d'};
  const abbreviatedDayAndMonth={type:'timeButton',formatTemplate:'EEE MMM d'};
  const long={type:'timeButton',formatTemplate:'EEEE, MMMM d, yyyy @ HH:mm'};
  assert.match(formatTimePreview(short.formatTemplate),/^\w{3} \d{1,2}$/);
  assert.equal(longestDateText('EEE MMM d'),'Wed Sep 31');
  assert.ok(widgetContentWidth(short) < 70, 'abbreviated month preview should not budget for a full month name or a decorative icon');
  assert.ok(widgetContentWidth(abbreviatedDayAndMonth) <= 90, 'abbreviated weekday and month tokens should remain abbreviated');
  assert.equal(widgetWidthForContent({...short,width:381},760/1085),Math.ceil(widgetContentWidth(short)/(760/1085)));
  assert.ok(widgetContentWidth(long)>widgetContentWidth(short));
  assert.ok(contentFitWidth(long)>64);
});

test('Fit-to-content width is explicit and does not rewrite existing manual layout sizing', () => {
  const date={id:'date',type:'timeButton',formatTemplate:'MMM d',width:381,studioPosition:650};
  const monitor={id:'monitor',type:'systemMonitor',metrics:['cpu','gpu','memory','temperature'],width:381,studioPosition:0};
  const before=structuredClone([date,monitor]);
  const fittedDate=widgetWidthForContent(date,760/1085);
  const fittedMonitor=widgetWidthForContent(monitor,760/1085);
  assert.ok(fittedDate<date.width);
  assert.ok(fittedMonitor<monitor.width);
  assert.equal(contentFitWidth(date),381);
  assert.equal(contentFitWidth(monitor),381);
  assert.deepEqual([date,monitor],before);
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
