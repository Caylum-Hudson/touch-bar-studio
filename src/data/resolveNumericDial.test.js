import test from 'node:test';
import assert from 'node:assert/strict';
import {elementTypes} from './elementDefinitions.js';
import {controlCatalog} from './controlCatalog.js';
import {generateJSON,parseJSON} from '../utils/jsonGenerator.js';
import {restoreWorkspaceProfiles,workspaceImportError} from '../utils/workspaceValidation.js';
import {isCurrentResolveNumericResponse,resolveNumericBindingError} from '../utils/resolveNumericDial.js';

const binding={version:1,zone:'Shadow',readout:'Exp',panelWidth:800,panelHeight:400,anchorX:0.4,anchorY:0.5,fingerprint:['Black','Dark','Shadow','Light','Highlight']};

test('Resolve Adjustment Dial is available with HDR defaults and native-sized width',()=>{
  const definition=elementTypes.resolveNumericDial;
  assert.equal(definition.type,'resolveNumericDial');
  assert.equal(definition.defaultProps.title,'HDR');
  assert.equal(definition.defaultProps.step,0.01);
  assert.equal(definition.defaultProps.width,110);
  assert.match(definition.defaultProps.matchAppId,/DaVinciResolve/);
  assert.ok(controlCatalog.some(group=>group.controls.some(control=>control.type==='resolveNumericDial')));
});

test('captured HDR binding and custom label survive config generation and parsing',()=>{
  const config=JSON.parse(generateJSON([{id:'dial-1',type:'resolveNumericDial',title:'Shadows',step:0.1,binding,width:110,matchAppId:'^com\\.blackmagic-design\\.DaVinciResolve$'}]));
  assert.deepEqual(config[0].binding,binding);
  assert.equal(config[0].title,'Shadows');
  assert.equal(config[0].step,0.1);
  const parsed=parseJSON(JSON.stringify(config));
  assert.equal(parsed.error,null);
  assert.deepEqual(parsed.items[0].binding,binding);
});

test('Resolve workspace restore keeps valid bindings and rejects stale-shaped geometry',()=>{
  const workspace={version:1,profiles:{default:{items:[{type:'staticButton'}]},resolve:{enabled:true,bundleId:'com.blackmagic-design.DaVinciResolve',items:[],resolvePageLayouts:{color:[{type:'resolveNumericDial',title:'HDR',step:0.01,binding}]}}}};
  assert.equal(workspaceImportError(workspace),null);
  const restored=restoreWorkspaceProfiles(workspace);
  assert.deepEqual(restored.resolve.resolvePageLayouts.color[0].binding,binding);
  const malformed=structuredClone(workspace);
  malformed.profiles.resolve.resolvePageLayouts.color[0].binding.anchorX=1.2;
  assert.match(workspaceImportError(malformed),/invalid panel geometry/);
});

test('HDR binding validation rejects unknown zones and invalid step response identity',()=>{
  assert.match(resolveNumericBindingError({...binding,zone:'Whites'}),/unsupported/);
  const operation={id:'dial-a',generation:3};
  assert.equal(isCurrentResolveNumericResponse(operation,{id:'dial-a',generation:3},{id:'dial-a'}),true);
  assert.equal(isCurrentResolveNumericResponse(operation,{id:'dial-b',generation:3},{id:'dial-a'}),false);
  assert.equal(isCurrentResolveNumericResponse(operation,{id:'dial-a',generation:4},{id:'dial-a'}),false);
  assert.equal(isCurrentResolveNumericResponse(operation,{id:'dial-a',generation:3},{id:'dial-b'}),false);
});
