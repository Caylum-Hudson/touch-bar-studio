import fs from 'node:fs';
import assert from 'node:assert/strict';
import {elementTypes,createElement} from '../src/data/elementDefinitions.js';
import {getControlInfo,controlCatalog,advancedControlCatalog} from '../src/data/controlCatalog.js';
import {generateJSON,parseJSON} from '../src/utils/jsonGenerator.js';
const symbols=JSON.parse(fs.readFileSync('public/control-icons/symbols.json','utf8'));
const catalog=[...controlCatalog,...advancedControlCatalog].flatMap(group=>group.controls);
assert.equal(new Set(catalog.map(control=>control.key)).size,Object.keys(elementTypes).length);
const resolveControls=catalog.filter(control=>control.key.startsWith('resolve'));
assert.equal(resolveControls.length,12,'Resolve timeline palette coverage');
for (const control of resolveControls) {
  const item=createElement(control.key);
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
const fixtures=Object.keys(elementTypes).map(key=>{
  const info=getControlInfo(key);
  assert.ok(info && info.status && info.benefit,key);
  assert.ok(symbols[key],key);
  assert.ok(fs.statSync(`public/control-icons/${key}.png`).size>100,key);
  return {key,items:JSON.parse(generateJSON([createElement(key)]))};
});
assert.equal(fixtures.find(f=>f.key==='dateButton').items[0].formatTemplate,'MMM d');
assert.equal(fixtures.find(f=>f.key==='dateButton').items[0].type,'timeButton');
fs.writeFileSync('local-build/control-fixtures.generated.json',JSON.stringify(fixtures));
console.log(`PASS: all ${fixtures.length} palette entries have distinct catalog entries, capability descriptions, native icons and serializable defaults.`);
