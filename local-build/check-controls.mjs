import fs from 'node:fs';
import assert from 'node:assert/strict';
import {elementTypes,createElement} from '../src/data/elementDefinitions.js';
import {getControlInfo,controlCatalog,advancedControlCatalog} from '../src/data/controlCatalog.js';
import {generateJSON,parseJSON} from '../src/utils/jsonGenerator.js';
const symbols=JSON.parse(fs.readFileSync('public/control-icons/symbols.json','utf8'));
assert.deepEqual(['cpu','ramUsage','gpuUsage'].map(key=>symbols[key]),['cpu','memorychip','display'],
  'legacy CPU, RAM and GPU icons remain available for existing layouts');
assert.equal(symbols.cpuTemperature,'thermometer.medium','CPU temperature uses a thermometer icon');
const catalog=[...controlCatalog,...advancedControlCatalog].flatMap(group=>group.controls);
assert.equal(new Set(catalog.map(control=>control.key)).size,Object.keys(elementTypes).length-5,
  'legacy metric controls remain decodable while the new System Monitor replaces them in the palette');
assert.equal(catalog.some(control=>control.key==='boardTemperature'),false,
  'unavailable motherboard temperature is hidden from the addable palette');
for (const key of ['cpu','ramUsage','gpuUsage','cpuTemperature']) {
  assert.equal(catalog.some(control=>control.key===key),false,`${key} remains supported for existing layouts, but is not a new palette control`);
}
assert.ok(catalog.some(control=>control.key==='systemMonitor'),'System Monitor replaces the four separate metric controls');
const resolveControls=catalog.filter(control=>control.key.startsWith('resolve'));
assert.equal(resolveControls.length,15,'Resolve shortcuts and Resolve-specific inline widgets remain in the palette');
for (const control of resolveControls) {
  const item=createElement(control.key);
  if (['resolveColorDial','resolveNumericDial','resolveTimelineJog'].includes(control.key)) {
    assert.equal(item.type,control.key,control.key);
    assert.match(item.matchAppId,/DaVinciResolve/,control.key);
    const reloaded=parseJSON(generateJSON([item])).items[0];
    assert.equal(reloaded.type,control.key,control.key);
    assert.equal(getControlInfo(reloaded.type,reloaded)?.key,control.key,`${control.key} keeps its palette identity after reload`);
    continue;
  }
  assert.equal(item.type,'staticButton',control.key);
  assert.match(item.matchAppId,/DaVinciResolve/,control.key);
  assert.equal(item.actions?.[0]?.action,'keyPress',control.key);
  assert.equal(typeof item.actions?.[0]?.keycode,'number',control.key);
  const reloaded=parseJSON(generateJSON([item])).items[0];
  assert.equal(reloaded.type,'staticButton',control.key);
  assert.equal(reloaded.matchAppId,item.matchAppId,control.key);
  assert.deepEqual(reloaded.actions.map(({id,...action})=>action),item.actions,control.key);
  assert.equal(getControlInfo(reloaded.type,reloaded)?.key,control.key,`${control.key} keeps its palette identity after reload`);
}
const fixtures=catalog.map(({key})=>{
  const info=getControlInfo(key);
  assert.ok(info && info.status && info.benefit,key);
  if (!['resolveColorDial','resolveNumericDial','resolveTimelineJog'].includes(key)) {
    assert.ok(symbols[key],key);
    assert.ok(fs.statSync(`public/control-icons/${key}.png`).size>100,key);
  }
  return {key,items:JSON.parse(generateJSON([createElement(key)]))};
});
const monitor=createElement('systemMonitor');
const monitorJSON=JSON.parse(generateJSON([monitor]));
assert.equal(monitorJSON[0].type,'systemMonitor');
assert.deepEqual(monitorJSON[0].metrics,['cpu','gpu','memory','temperature']);
assert.equal(Object.hasOwn(monitorJSON[0],'title'),false,'System Monitor starts without a placeholder title');
assert.deepEqual(parseJSON(JSON.stringify(monitorJSON)).items[0].metrics,monitor.metrics,'metric selection survives editor serialization');
assert.equal(elementTypes.boardTemperature.type,'boardTemperature', 'legacy saved motherboard entries remain recognizable');
assert.equal(fixtures.find(f=>f.key==='dateButton').items[0].formatTemplate,'MMM d');
assert.equal(fixtures.find(f=>f.key==='dateButton').items[0].type,'timeButton');
fs.writeFileSync('local-build/control-fixtures.generated.json',JSON.stringify(fixtures));
console.log(`PASS: all ${fixtures.length} palette entries have distinct catalog entries, capability descriptions, native icons and serializable defaults.`);
