import React, {useEffect, useState} from 'react';
import {createRoot} from 'react-dom/client';
import {DndContext,PointerSensor,useSensor,useSensors} from '@dnd-kit/core';
import {AppProvider,useApp} from '../src/context/AppContext';
import {RuntimePermissionsProvider} from '../src/context/RuntimePermissions';
import TouchBar from '../src/components/TouchBar/TouchBar';
import PropertiesPanel from '../src/components/Properties/PropertiesPanel';
import {distributeItemsEvenly} from '../src/utils/positionLayout.js';
import '../src/StudioShell.css';
import '../src/StudioTheme.css';

const fixtureItems=[
  {id:'resolve-lift-y',type:'resolveColorDial',parameter:'lift',channel:'Y',sensitivity:'fine',width:90,align:'left'},
  {id:'resolve-gamma-y',type:'resolveColorDial',parameter:'gamma',channel:'Y',sensitivity:'fine',width:90,align:'left'},
  {id:'resolve-gain-y',type:'resolveColorDial',parameter:'gain',channel:'Y',sensitivity:'fine',width:90,align:'left'},
  {id:'resolve-hdr-dial',type:'resolveNumericDial',title:'HDR',step:0.01,width:110,align:'left'},
  {id:'resolve-jog',type:'resolveTimelineJog',sensitivity:'fine',width:140,align:'left'},
];

export function Fixture(){
  const [previewScalePercent,setPreviewScalePercent]=useState(100);
  const {loadItems}=useApp();
  const sensors=useSensors(useSensor(PointerSensor,{activationConstraint:{distance:5}}));
  useEffect(()=>loadItems(distributeItemsEvenly(fixtureItems,{availableWidth:1085,contentScale:685/1085})),[loadItems]);
  return <main className="studio-shell" style={{padding:20}}>
    <header style={{marginBottom:18}}><strong>Resolve inline controls · isolated preview</strong><p>685 pt layout capacity · macOS Control Strip shown separately · all dial values are illustrative only.</p><label>Fixture preview scale: {previewScalePercent}% <input aria-label="Fixture preview scale" type="range" min="50" max="200" step="5" value={previewScalePercent} onChange={event=>setPreviewScalePercent(+event.target.value)}/></label></header>
    <DndContext sensors={sensors}>
      <RuntimePermissionsProvider native keepControlStrip layoutCapacity={{physicalWidth:685,logicalWidth:1085,keepControlStrip:true}} previewScalePercent={previewScalePercent} updatePreviewScalePercent={setPreviewScalePercent}>
        <div style={{display:'grid',gridTemplateColumns:'minmax(0,1fr) 340px',gap:16}}><TouchBar/><PropertiesPanel/></div>
      </RuntimePermissionsProvider>
    </DndContext>
  </main>;
}

createRoot(document.getElementById('root')).render(<AppProvider><Fixture/></AppProvider>);
