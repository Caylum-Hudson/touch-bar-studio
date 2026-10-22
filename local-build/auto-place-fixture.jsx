import React from 'react';
import {createRoot} from 'react-dom/client';
import {DndContext} from '@dnd-kit/core';
import {AppProvider, useApp} from '../src/context/AppContext';
import {RuntimePermissionsProvider} from '../src/context/RuntimePermissions';
import TouchBar from '../src/components/TouchBar/TouchBar';
import '../src/StudioShell.css';

const fitting = [
  {id:'volume',type:'volume',width:80,studioPosition:20},
  {id:'brightness',type:'brightness',width:80,studioPosition:70},
  {id:'cpu',type:'cpu',width:24,studioPosition:400},
  {id:'ram',type:'ramUsage',width:24,studioPosition:700},
];
const overflowing = Array.from({length:3},(_,index)=>({id:`wide-${index}`,type:'volume',width:400,studioPosition:index*200}));
localStorage.setItem('touchbar-studio-profiles',JSON.stringify({default:{id:'default',name:'Fixture',enabled:true,items:fitting}}));
localStorage.removeItem('mtmr-designer-items');

function Fixture() {
  const app=useApp();
  return <div className="studio-shell" style={{padding:20}}>
    <header style={{display:'flex',gap:12,alignItems:'center',marginBottom:20}}><strong>Isolated auto-placement fixture</strong><span>Native capacity: 760 px custom region; Control Strip reserved separately.</span><button onClick={()=>app.loadItems(fitting)}>Load fitting layout</button><button onClick={()=>app.loadItems(overflowing)}>Load no-fit layout</button><button disabled={!app.canUndo} onClick={app.undo}>Undo</button></header>
    <DndContext><RuntimePermissionsProvider native keepControlStrip layoutCapacity={{physicalWidth:760,logicalWidth:1085,keepControlStrip:true}}><TouchBar/></RuntimePermissionsProvider></DndContext>
    <pre id="fixture-layout" style={{fontSize:11,marginTop:24}}>{JSON.stringify(app.items,null,2)}</pre>
  </div>;
}
createRoot(document.getElementById('root')).render(<AppProvider><Fixture/></AppProvider>);
