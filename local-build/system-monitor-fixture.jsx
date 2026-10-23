import React from 'react';
import {createRoot} from 'react-dom/client';
import {DndContext,PointerSensor,useSensor,useSensors} from '@dnd-kit/core';
import {AppProvider, useApp} from '../src/context/AppContext';
import {RuntimePermissionsProvider} from '../src/context/RuntimePermissions';
import TouchBar from '../src/components/TouchBar/TouchBar';
import PropertiesPanel from '../src/components/Properties/PropertiesPanel';
import '../src/StudioShell.css';

const legacy=[
  {id:'cpu',type:'cpu',width:64,align:'left',studioPosition:96},
  {id:'ram',type:'ramUsage',width:64,align:'left',studioPosition:168},
  {id:'gpu',type:'gpuUsage',width:64,align:'left',studioPosition:240},
  {id:'temp',type:'cpuTemperature',width:64,align:'left',studioPosition:312},
  {id:'keep',type:'staticButton',title:'Keep position',width:96,align:'left',studioPosition:560},
];
const withMonitor=[...legacy.slice(0,2),{id:'monitor',type:'systemMonitor',metrics:['cpu'],width:64,align:'left',studioPosition:240},...legacy.slice(2)];
function Fixture(){
  const app=useApp();
  const sensors=useSensors(useSensor(PointerSensor,{activationConstraint:{distance:5}}));
  return <div className="studio-shell" style={{padding:20}}>
    <header style={{display:'flex',gap:10,alignItems:'center',marginBottom:18,flexWrap:'wrap'}}><strong>Isolated System Monitor QA</strong><span>Native capacity: 760 px; Control Strip reserved.</span><button onClick={()=>app.loadItems(legacy)}>Load four legacy readings</button><button onClick={()=>app.loadItems(withMonitor)}>Load legacy + monitor</button><button disabled={!app.canUndo} onClick={app.undo}>Undo</button><button onClick={()=>app.loadItems([{id:'monitor-only',type:'systemMonitor',metrics:['cpu','gpu','memory','temperature'],width:64,align:'left',studioPosition:100}])}>Load new monitor</button></header>
    <DndContext sensors={sensors}><RuntimePermissionsProvider native keepControlStrip layoutCapacity={{physicalWidth:760,logicalWidth:1085,keepControlStrip:true}}><div style={{display:'grid',gridTemplateColumns:'minmax(0,1fr) 340px',gap:16}}><TouchBar/><PropertiesPanel/></div></RuntimePermissionsProvider></DndContext>
    <pre id="fixture-layout" style={{fontSize:11,marginTop:20,whiteSpace:'pre-wrap'}}>{JSON.stringify({items:app.items,selectedItemId:app.selectedItemId,canUndo:app.canUndo},null,2)}</pre>
  </div>;
}
createRoot(document.getElementById('root')).render(<AppProvider><Fixture/></AppProvider>);
