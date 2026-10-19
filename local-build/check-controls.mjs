import fs from 'node:fs';
import assert from 'node:assert/strict';
import {elementTypes,createElement} from '../src/data/elementDefinitions.js';
import {getControlInfo,controlCatalog,advancedControlCatalog} from '../src/data/controlCatalog.js';
import {generateJSON} from '../src/utils/jsonGenerator.js';
const symbols=JSON.parse(fs.readFileSync('public/control-icons/symbols.json','utf8'));
const catalog=[...controlCatalog,...advancedControlCatalog].flatMap(group=>group.controls);
assert.equal(new Set(catalog.map(control=>control.key)).size,Object.keys(elementTypes).length);
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
