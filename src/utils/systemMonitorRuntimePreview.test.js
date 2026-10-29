import test from 'node:test';
import assert from 'node:assert/strict';
import {cloneWithoutRuntimeIdentity,generateJSON} from './jsonGenerator.js';
import {matchSystemMonitorRuntimePreviews, systemMonitorConfigurationSignature} from './systemMonitorRuntimePreview.js';
import {restoreWorkspaceProfiles} from './workspaceValidation.js';

const monitor = overrides => ({id:'monitor-id',type:'systemMonitor',metrics:['cpu','gpu','memory','temperature'],autoFitContent:true,...overrides});
const fixtureProfile = (items, extras = {}) => ({bundleId:'',items,...extras});
const rowFor = item => ({
  studioId:item.id,
  metrics:item.metrics,
  title:'8% · 0% · 42% · 57°C',
  naturalWidth:178,
  frameWidth:178,
  signature:systemMonitorConfigurationSignature(item),
});
const match = ({item=monitor(), profile=fixtureProfile([item]), row=rowFor(item), ...overrides}={}) => matchSystemMonitorRuntimePreviews({
  rows:[row],profiles:{default:profile},profileId:'default',resolvePageId:'fallback',groupPath:[],
  activeProfile:'default',activeResolvePage:null,activeGroupPath:[],runtimeEnabled:true,...overrides,
});

test('generated runtime metadata uses current editor IDs and only tags monitor ancestors', () => {
  const json = JSON.parse(generateJSON([
    {id:'parent',studioId:'stale-parent',type:'group',items:[monitor({studioId:'stale-monitor'})]},
    {id:'unrelated',type:'staticButton',title:'Other'},
  ]));
  assert.equal(json[0].studioId,'parent');
  assert.equal(json[0].items[0].studioId,'monitor-id');
  assert.match(json[0].items[0].studioPreviewSignature,/^[a-f0-9]{8}$/);
  assert.equal('studioId' in json[1],false);
});

test('duplicating a nested monitor clears old runtime identity so the copy receives fresh IDs', () => {
  const source={id:'old-group',studioId:'old-group-runtime',preserveStudioId:true,type:'group',items:[{
    id:'old-monitor',studioId:'old-monitor-runtime',preserveStudioId:true,studioPreviewSignature:'deadbeef',type:'systemMonitor',metrics:['cpu'],
  }]};
  const duplicate=cloneWithoutRuntimeIdentity(source);
  assert.equal(duplicate.type,'group');
  assert.equal('id' in duplicate,false);
  assert.equal('studioId' in duplicate,false);
  assert.equal('preserveStudioId' in duplicate,false);
  assert.equal('id' in duplicate.items[0],false);
  assert.equal('studioId' in duplicate.items[0],false);
  assert.equal('preserveStudioId' in duplicate.items[0],false);
  assert.equal('studioPreviewSignature' in duplicate.items[0],false);
  const serialized=JSON.parse(generateJSON([{...duplicate,id:'new-group',items:[{...duplicate.items[0],id:'new-monitor'}]}]));
  assert.equal(serialized[0].studioId,'new-group');
  assert.equal(serialized[0].items[0].studioId,'new-monitor');
});

test('live widths and titles match only the active saved monitor configuration', () => {
  const item = monitor();
  const result = match({item});
  assert.equal(result.get(item.id).title,'8% · 0% · 42% · 57°C');
  assert.equal(result.get(item.id).contentWidth,178);
  assert.equal(result.get(item.id).frameWidth,178);
  assert.equal(match({item,row:{...rowFor(item),metrics:['cpu']}}).size,0);
  assert.equal(match({item:monitor({autoFitContent:false})}).size,0);
  assert.equal(match({item,row:{...rowFor(item),signature:'stale'}}).size,0);
  assert.equal(match({item,activeProfile:'resolve'}).size,0);
  assert.equal(match({item,activeResolvePage:'color'}).size,0);
  assert.equal(match({item,activeGroupPath:['some-group']}).size,0);
  assert.equal(match({item,runtimeEnabled:false}).size,0);
});

test('Default and Resolve fallback read profile items even when page-layout maps are empty', () => {
  const item = monitor();
  assert.equal(match({item,profile:fixtureProfile([item],{resolvePageLayouts:{}})}).size,1);
  const resolveProfile = fixtureProfile([item],{bundleId:'com.blackmagic-design.DaVinciResolve',resolvePageLayouts:{}});
  assert.equal(match({item,profile:resolveProfile,resolvePageId:'fallback'}).size,1);
  assert.equal(match({item,profile:resolveProfile,resolvePageId:'edit',activeResolvePage:'edit'}).size,0);
});

test('nested monitor live data requires the exact active group path and uses nested IDs', () => {
  const item = monitor();
  const group = {id:'nested-id',type:'group',items:[item]};
  const profile = fixtureProfile([{id:'outer-id',type:'group',items:[group]}]);
  const row = rowFor(item);
  const matched = matchSystemMonitorRuntimePreviews({rows:[row],profiles:{default:profile},profileId:'default',resolvePageId:null,groupPath:['outer-id','nested-id'],activeProfile:'default',activeResolvePage:null,activeGroupPath:['outer-id','nested-id'],runtimeEnabled:true});
  assert.equal(matched.get(item.id).contentWidth,178);
  const wrong = matchSystemMonitorRuntimePreviews({rows:[row],profiles:{default:profile},profileId:'default',resolvePageId:null,groupPath:['outer-id','other'],activeProfile:'default',activeResolvePage:null,activeGroupPath:['outer-id','other'],runtimeEnabled:true});
  assert.equal(wrong.size,0);
});

test('workspace restore and reapply preserve stable native monitor IDs at root and nested levels', () => {
  for (const nested of [false,true]) {
    const original=monitor();
    const originalItems=nested ? [{id:'outer',type:'group',items:[{id:'inner',type:'group',items:[original]}]}] : [original];
    const nativeItems=JSON.parse(generateJSON(originalItems));
    const profiles=restoreWorkspaceProfiles({version:1,profiles:{default:fixtureProfile(nativeItems)}});
    const outer=profiles.default.items[0];
    const inner=nested ? outer.items[0] : null;
    const restored=nested ? inner.items[0] : outer;
    assert.notEqual(restored.id,original.id);
    assert.equal(restored.studioId,original.id);
    const context={rows:[rowFor(original)],profiles,profileId:'default',groupPath:nested?[outer.id,inner.id]:[],activeProfile:'default',activeGroupPath:nested?['outer','inner']:[],runtimeEnabled:true};
    assert.equal(matchSystemMonitorRuntimePreviews(context).get(restored.id).contentWidth,178);
    const reapplied=JSON.parse(generateJSON(profiles.default.items));
    assert.equal((nested?reapplied[0].items[0].items[0]:reapplied[0]).studioId,original.id);
    assert.equal(matchSystemMonitorRuntimePreviews(context).size,1,'the saved native ID remains matchable after Apply & Save');
    restored.background='#123456';
    assert.equal(matchSystemMonitorRuntimePreviews(context).size,0,'a retained ID must not bypass the configuration signature');
  }
});

test('ambiguous restored monitor and group aliases do not attach live data', () => {
  const original=monitor();
  const one={...original,id:'new-one',studioId:original.id};
  const two={...original,id:'new-two',studioId:original.id};
  assert.equal(match({profile:fixtureProfile([one,two]),row:rowFor(original)}).size,0);
  const groups=[{id:'group-one',studioId:'old-group',type:'group',items:[one]},{id:'group-two',studioId:'old-group',type:'group',items:[two]}];
  assert.equal(match({profile:fixtureProfile(groups),row:rowFor(original),groupPath:['group-one'],activeGroupPath:['old-group']}).size,0);
});
