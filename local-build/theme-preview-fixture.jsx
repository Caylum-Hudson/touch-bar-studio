import React, {useEffect} from 'react';
import {createRoot} from 'react-dom/client';
import {AppProvider, useApp} from '../src/context/AppContext';
import {RuntimePermissionsProvider} from '../src/context/RuntimePermissions';
import {AppContent} from '../src/App';
import {themeTokens} from '../src/utils/themeTokens';
import '../src/StudioShell.css';
import '../src/StudioTheme.css';

const apps=Array.from({length:7},(_,index)=>({bundleId:`fixture.app${index}`,name:`App ${index+1}`,running:index===0,iconData:`data:image/svg+xml,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="7" fill="hsl(${index*48} 70% 55%)"/><text x="16" y="21" text-anchor="middle" font-size="16" fill="white">${index+1}</text></svg>`)}`}));
const fixtureItems=[
  {id:'dock-fixture',type:'dock',align:'left',width:252,autoResize:false,studioPosition:0},
  {id:'monitor-fixture',type:'systemMonitor',metrics:['cpu','gpu','memory','temperature'],align:'left',width:381,studioPosition:310},
  {id:'time-fixture',type:'timeButton',formatTemplate:'HH:mm',align:'left',width:78,studioPosition:720},
];

function Fixture(){
  const app=useApp();
  const [background,setBackground]=React.useState('#14151d');
  const [accent,setAccent]=React.useState('#32a86f');
  const [narrow,setNarrow]=React.useState(false);
  const [viewportWidth,setViewportWidth]=React.useState(window.innerWidth);
  useEffect(()=>{app.loadItems(fixtureItems);app.selectItem('monitor-fixture');},[]);
  useEffect(()=>{const resize=()=>setViewportWidth(window.innerWidth);window.addEventListener('resize',resize);return()=>window.removeEventListener('resize',resize);},[]);
  const themes=[['Green','#32a86f','#183325'],['Magenta','#d946ef','#201126'],['Light','#bb567a','#f2efdf']];
  return <main className={`studio-shell fixture-shell ${narrow?'narrow-preview':''}`} style={{...themeTokens(background,accent)}}>
    <style>{`.fixture-shell{height:100vh;overflow:hidden}.fixture-shell .fixture-controls{height:42px;flex:0 0 42px;display:flex;align-items:center;gap:8px;padding:0 14px;background:var(--studio-surface);border-bottom:1px solid var(--studio-border)}.fixture-shell .fixture-controls span{color:var(--studio-muted);margin-right:auto}.fixture-shell .fixture-controls button{padding:5px 8px;font-size:11px}.fixture-shell>.app{height:auto;min-height:0;flex:1}.fixture-shell.narrow-preview .sidebar-left{display:none!important}.fixture-shell.narrow-preview .sidebar-right{width:210px!important}.fixture-state{position:fixed;z-index:20;left:10px;bottom:8px;max-width:320px;max-height:110px;overflow:auto;padding:5px 8px;border:1px solid var(--studio-border);border-radius:5px;background:var(--studio-surface);color:var(--studio-text);font-size:9px;opacity:.85}.fixture-state summary{cursor:pointer}.fixture-state pre{white-space:pre-wrap;margin:5px 0}`}</style>
    <div className="fixture-controls"><strong>Theme and preview QA</strong><span>Live editor · 760 pt native width · 30 pt control row</span>{themes.map(([name,nextAccent,nextBackground])=><button key={name} onClick={()=>{setAccent(nextAccent);setBackground(nextBackground)}}>{name}</button>)}<button onClick={()=>app.selectItem('monitor-fixture')}>Select monitor</button><button onClick={()=>setNarrow(value=>!value)}>{narrow?'Restore width':'Fit narrow'}</button><button onClick={()=>app.loadItems(fixtureItems)}>Reload Dock + System Monitor + Time</button></div>
    <RuntimePermissionsProvider native keepControlStrip layoutCapacity={{physicalWidth:760,logicalWidth:1085,keepControlStrip:true}}><AppContent dockPreviewOverride={{apps,preferredWidth:164,iconSize:32,itemSpacing:1}}/></RuntimePermissionsProvider>
    <details className="fixture-state" id="fixture-state"><summary>Fixture state · viewport {viewportWidth}px{narrow?' · narrow':''}</summary><pre>{JSON.stringify({items:app.items,selectedItemId:app.selectedItemId,background,accent,nativeWidth:760,expectedSystemMonitorNativeWidth:381*760/1085},null,2)}</pre></details>
  </main>;
}

createRoot(document.getElementById('root')).render(<AppProvider><Fixture/></AppProvider>);
