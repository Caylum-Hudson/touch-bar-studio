import {build} from 'esbuild';
import fs from 'node:fs';
import assert from 'node:assert/strict';
globalThis.localStorage={getItem(){return null},setItem(){}};
const source=fs.readFileSync('src/context/AppContext.jsx','utf8')+'\nexport {appReducer,initialState};';
await build({stdin:{contents:source,resolveDir:process.cwd()+'/src/context',loader:'jsx'},bundle:true,platform:'node',format:'esm',outfile:'local-build/test-state.generated.mjs'});
const {appReducer,initialState}=await import('./test-state.generated.mjs');
let s=structuredClone(initialState);
const reducer=a=>s=appReducer(s,a);
reducer({type:'ADD_ITEM',payload:{item:{id:'outer',type:'group',items:[{id:'inner',type:'group',items:[]}]}}});
reducer({type:'ADD_ITEM',payload:{item:{id:'button',type:'staticButton',title:'original'},parentId:'inner'}});
reducer({type:'UPDATE_ITEM',payload:{id:'button',updates:{title:'changed'}}});
assert.equal(s.items.at(-1).items[0].items[0].title,'changed');
reducer({type:'MOVE_ITEM',payload:{id:'button',target:null}});
assert.equal(s.items.at(-1).id,'button');assert.equal(s.items.find(i=>i.id==='outer').items[0].items.length,0);
reducer({type:'UNDO'});assert.equal(s.items.at(-1).items[0].items[0].id,'button');assert.equal(s.isDirty,true);
reducer({type:'REDO'});assert.equal(s.items.at(-1).id,'button');
const before=JSON.stringify(s.items);
reducer({type:'MOVE_ITEM',payload:{id:'outer',target:'inner'}});assert.equal(JSON.stringify(s.items),before);
reducer({type:'PROFILE_SET',payload:{...s.profiles,test:{id:'test',name:'Finder',bundleId:'com.apple.finder',enabled:true,items:[{id:'finder',type:'escape'}]}}});
reducer({type:'PROFILE_SWITCH',payload:'test'});assert.equal(s.items[0].id,'finder');
reducer({type:'PROFILE_SWITCH',payload:'default'});assert.equal(JSON.stringify(s.items),before);
reducer({type:'WORKSPACE_LOAD',payload:{version:1,profiles:{default:{items:[{type:'group',future:{x:7},items:[{type:'staticButton',title:'restored'}]}]}}}});
assert.ok(s.items[0].id);assert.ok(s.items[0].items[0].id);assert.equal(s.items[0].future.x,7);
const validWorkspaceState=s;
reducer({type:'WORKSPACE_LOAD',payload:{version:1,profiles:{default:{items:[{}]}}}});
assert.equal(s,validWorkspaceState,'Malformed workspace restore must preserve the complete editor state');
const {parseJSON,generateJSON}=await import('../src/utils/jsonGenerator.js');
const resolveFallback=[{id:'fallback',type:'staticButton',title:'Fallback'}];
const resolveEdit=[{id:'edit',type:'staticButton',title:'Edit'}];
const resolveColor=[{id:'color',type:'staticButton',title:'Color'}];
reducer({type:'PROFILE_SET',payload:{
  default:{id:'default',items:resolveFallback},
  resolve:{id:'resolve',name:'Resolve',bundleId:'com.blackmagic-design.DaVinciResolve',items:resolveFallback,resolvePageLayouts:{edit:resolveEdit,color:resolveColor}},
}});
reducer({type:'PROFILE_SWITCH',payload:'resolve'});
assert.equal(s.resolvePageId,'edit');assert.equal(s.items[0].title,'Edit');
reducer({type:'RESOLVE_PAGE_SWITCH',payload:'color'});
reducer({type:'UPDATE_ITEM',payload:{id:'color',updates:{title:'Color edited'}}});
reducer({type:'RESOLVE_PAGE_SWITCH',payload:'edit'});
assert.equal(s.profiles.resolve.resolvePageLayouts.color[0].title,'Color edited');
reducer({type:'RESOLVE_PAGE_SWITCH',payload:'fusion'});
assert.equal(s.resolvePageReady,false);assert.equal(s.profiles.resolve.resolvePageLayouts.fusion,undefined);
reducer({type:'PROFILE_SWITCH',payload:'default'});
assert.equal(s.profiles.resolve.resolvePageLayouts.fusion,undefined,'Switching away from a missing page must not create an empty layout');
assert.equal(s.profiles.resolve.items[0].title,'Fallback','Editing a page must not overwrite the profile fallback');
reducer({type:'PROFILE_SWITCH',payload:'resolve'});
assert.equal(s.resolvePageId,'edit');assert.equal(s.items[0].title,'Edit');
reducer({type:'RESOLVE_PAGE_SWITCH',payload:'fusion'});
reducer({type:'RESOLVE_PAGE_CREATE',payload:{pageId:'fusion',items:resolveFallback.map(item=>({...item}))}});
assert.equal(s.profiles.resolve.resolvePageLayouts.fusion[0].title,'Fallback');
assert.equal(s.profiles.resolve.resolvePageLayouts.color[0].title,'Color edited');
const serializedResolve=JSON.parse(generateJSON(s.profiles.resolve.resolvePageLayouts.color));
assert.equal(parseJSON(JSON.stringify(serializedResolve)).items[0].title,'Color edited');
assert.equal(s.profiles.resolve.items[0].title,'Fallback');
console.log('PASS: Resolve per-page reducer isolation, missing-page/profile-switch fallback, explicit layout creation, and page JSON round trip.');
const original=[{type:'group',future:{x:7},items:[{type:'unreleasedWidget',custom:42,actions:[{trigger:'singleTap',action:'futureAction',future:9}]}]}];
const parsed=parseJSON(JSON.stringify(original));assert.equal(parsed.error,null);
const output=JSON.parse(generateJSON(parsed.items));assert.equal(output[0].future.x,7);assert.equal(output[0].items[0].custom,42);assert.equal(output[0].items[0].actions[0].future,9);assert.equal(output[0].id,undefined);
assert.equal(parseJSON('[{"type":"staticButton","title":"https://example.com"}, // comment\n]').items[0].title,'https://example.com');
console.log('PASS: nested editing, cycle prevention, root moves, undo/redo, complete profile replacement, restore IDs, unknown-field round trip, commented JSON.');

assert.equal(parseJSON('[{"type":"staticButton","title":",] and ,}"}]').items[0].title,',] and ,}');
assert.ok(parseJSON('[{"title":"missing type"}]').error);
console.log('PASS: trailing commas do not corrupt strings; invalid controls produce an import error.');
const modifiedShortcut=[{type:'staticButton',title:'+Serial',actions:[{trigger:'singleTap',action:'keyPress',keycode:1,modifiers:['option']}]}];
const modifierRoundtrip=JSON.parse(generateJSON(parseJSON(JSON.stringify(modifiedShortcut)).items));
assert.deepEqual(modifierRoundtrip[0].actions[0].modifiers,['option']);
console.log('PASS: simultaneous shortcut modifiers survive editor JSON serialization.');

const {layoutFrames,clampPosition,overlappingItems,contentMinimumWidth,combineLegacySystemMetrics}=await import('../src/utils/positionLayout.js');
const positioned=[{id:'left',type:'staticButton',align:'left',width:50,studioPosition:120},{id:'right',type:'staticButton',align:'right',width:100,studioPosition:985}];
const fittedLeft=layoutFrames(positioned).get('left');
assert.equal(fittedLeft.x,120);assert.equal(fittedLeft.width,Math.max(50,contentMinimumWidth(positioned[0])));assert.equal(positioned[0].width,50);
assert.equal(clampPosition(1080,100),985);assert.equal(clampPosition(-20,64),0);
assert.equal(overlappingItems(positioned),false);assert.equal(overlappingItems([...positioned,{id:'overlap',width:50,studioPosition:130}]),true);
const roundtrip=JSON.parse(generateJSON(parseJSON(JSON.stringify(positioned)).items));assert.equal(roundtrip[0].studioPosition,120);
console.log('PASS: precise positions, boundary clamping, overlap detection and JSON position round trip.');

const {setConsistentSpacing,snapPosition,spacingGap,nextSpacedPosition}=await import('../src/utils/positionLayout.js');
const spaced=setConsistentSpacing([{id:'a',width:40,studioPosition:0},{id:'b',width:60,studioPosition:300},{id:'c',width:40,studioPosition:600}],12);
assert.deepEqual(spaced.map(item=>item.studioPosition),[0,52,124]);
assert.equal(spacingGap(spaced),12);
assert.deepEqual(snapPosition(spaced,'b',57,60),{x:52,snapped:true});
assert.deepEqual(snapPosition(spaced,'b',400,60),{x:400,snapped:false});
const detached=[{id:'a',width:40,studioPosition:0,studioGap:12},{id:'b',width:40,studioPosition:52,studioGap:12},{id:'c',width:40,studioPosition:500,studioGap:12}];
assert.deepEqual(snapPosition(detached,null,558,40),{x:552,snapped:true});
assert.deepEqual(setConsistentSpacing(detached,20).map(item=>item.studioPosition),[0,60,500]);
assert.equal(nextSpacedPosition(spaced,40),176);
assert.throws(()=>setConsistentSpacing([{id:'a',width:600,studioPosition:0},{id:'b',width:600,studioPosition:200}],20),/Not enough room/);
assert.equal(JSON.parse(generateJSON(spaced.map(item=>({...item,type:"staticButton"}))))[0].studioGap,12);
console.log('PASS: equal edge gaps, local cluster snapping, free placement, detached anchors, insertion, overflow and spacing persistence.');

const originalMetricBar=[
  {id:'cpu-old',type:'cpu',studioPosition:180,width:64},
  {id:'ram-old',type:'ramUsage',studioPosition:120,width:64},
  {id:'gpu-old',type:'gpuUsage',studioPosition:150,width:64},
  {id:'temp-old',type:'cpuTemperature',studioPosition:210,width:64},
  {id:'stay',type:'staticButton',title:'Keep',studioPosition:400,width:64},
];
reducer({type:'LOAD_ITEMS',payload:[{id:'submenu',type:'group',items:originalMetricBar}]});
const mergedBar=combineLegacySystemMetrics(originalMetricBar,'gpu-old');
reducer({type:'COMBINE_SYSTEM_MONITOR',payload:{...mergedBar,parentId:'submenu'}});
assert.equal(s.selectedItemId,'gpu-old');
assert.equal(s.items[0].items.length,2);
assert.deepEqual(s.items[0].items[0].metrics,['cpu','gpu','memory','temperature']);
assert.equal(s.items[0].items[1].id,'stay');
const exportedMonitor=JSON.parse(generateJSON(s.items[0].items))[0];
assert.deepEqual(exportedMonitor.metrics,['cpu','gpu','memory','temperature']);
reducer({type:'UNDO'});
assert.deepEqual(s.items[0].items,originalMetricBar,'One undo should restore every legacy metric and preserve the surrounding layout');
console.log('PASS: current-submenu combine/export stores one fixed-order monitor; one undo restores the complete legacy layout.');
