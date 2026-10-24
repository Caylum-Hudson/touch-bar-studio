import React,{useEffect,useRef,useState} from 'react';
import {createRoot} from 'react-dom/client';
import {AppProvider,useApp} from '../src/context/AppContext';
import {RuntimePermissionsProvider} from '../src/context/RuntimePermissions';
import {AppContent} from '../src/App';
import {selectedSystemMonitorMetrics} from '../src/utils/systemMonitor.js';
import {systemMonitorConfigurationSignature} from '../src/utils/systemMonitorRuntimePreview.js';
import '../src/StudioShell.css';
import '../src/StudioTheme.css';

const sampleTitles=['8% · 0% · 42% · 57°C','100% · 100% · 100% · 130°C'];
const initialItems=[
  {id:'live-monitor',type:'systemMonitor',metrics:['cpu','gpu','memory','temperature'],autoFitContent:true,width:376,align:'left',studioPosition:310},
  {id:'live-time',type:'timeButton',formatTemplate:'MMM d',width:102,align:'left',studioPosition:720},
];

export function Fixture(){
  const app=useApp();
  const initialized=useRef(false);
  const [sample,setSample]=useState(0);
  const [enabled,setEnabled]=useState(true);
  useEffect(()=>{
    if (initialized.current) return;
    initialized.current=true;
    app.restoreWorkspace({version:1,profiles:{default:{name:'Default',items:initialItems}},settings:{keepControlStrip:true}});
  },[app]);
  const monitor=app.items.find(item=>item.type==='systemMonitor');
  const rows=enabled&&monitor?.autoFitContent?[{studioId:monitor.id,metrics:selectedSystemMonitorMetrics(monitor),title:sampleTitles[sample],naturalWidth:sample?237:190,frameWidth:sample?237:190,signature:systemMonitorConfigurationSignature(monitor)}]:[];
  return <main className="studio-shell" style={{padding:18}}>
    <header style={{display:'flex',gap:10,alignItems:'center',marginBottom:14,flexWrap:'wrap'}}><strong>System Monitor live sizing QA · isolated fixture</strong><button onClick={()=>setSample(value=>1-value)}>Toggle short / long readings</button><button onClick={()=>setEnabled(value=>!value)}>Toggle runtime visibility</button></header>
    <RuntimePermissionsProvider native keepControlStrip layoutCapacity={{physicalWidth:760,logicalWidth:1085,keepControlStrip:true}} systemMonitorPreviews={rows} activeRuntimeProfile="default" activeRuntimeResolvePage={null} activeStudioGroupPath={[]} activeRuntimeEnabled={enabled}>
      <AppContent dockPreviewOverride={{apps:[],preferredWidth:null}} />
    </RuntimePermissionsProvider>
    <pre style={{fontSize:11,whiteSpace:'pre-wrap',marginTop:16}}>{JSON.stringify({item:monitor,liveRow:rows[0]||null,selectedItemId:app.selectedItemId},null,2)}</pre>
  </main>;
}

createRoot(document.getElementById('root')).render(<AppProvider><Fixture/></AppProvider>);
