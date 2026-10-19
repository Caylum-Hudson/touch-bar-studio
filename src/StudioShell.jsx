import { useState, useEffect, useRef } from 'react';
import { useApp } from './context/AppContext';
import { AppContent } from './App';
import { generateJSON } from './utils/jsonGenerator';
import './StudioShell.css';
const native = location.protocol === 'mtmr-app:';
async function api(route, data) {
  if (!native) throw new Error('Open Touch Bar Studio.app to use Mac integration.');
  const result = await fetch('/api/' + route, data ? {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)} : {}).then(r=>r.json());
  if (!result.success) throw new Error(result.error || 'The Mac action failed.');
  return result;
}
function download(name, data) {
  const url = URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));
  const a = document.createElement('a'); a.href=url; a.download=name; a.click(); setTimeout(()=>URL.revokeObjectURL(url),1000);
}
const defaults = {accent:'#a78bfa',background:'#14151d',motion:'off',tiles:[]};
export default function StudioShell() {
  const app = useApp();
  const [tab,setTab] = useState(document.documentElement.classList.contains('compact-launcher')?'Launcher':'Studio');
  const [settings,setSettings] = useState(()=> {try{return {...defaults,...JSON.parse(localStorage.getItem('studio-settings'))};}catch{return defaults;}});
  const [status,setStatus] = useState('Ready — changes are saved locally');
  const [active,setActive] = useState('default');
  const [enabled,setEnabled] = useState(null);
  const [toggling,setToggling] = useState(false);
  useEffect(()=>{
    if(enabled===null)return;
    setStatus(previous=>previous.startsWith('Custom Touch Bar')?(enabled?'Custom Touch Bar on':'Custom Touch Bar off · macOS controls restored'):previous);
  },[enabled]);
  const [pendingPhotos,setPendingPhotos] = useState(null);
  const [apps,setApps] = useState([]);
  const [name,setName] = useState('');
  const [bundle,setBundle] = useState('');
  const importRef=useRef(null);
  useEffect(()=>{localStorage.setItem('studio-settings',JSON.stringify(settings));},[settings]);
  useEffect(()=>{
    if(!native)return;
    api('studio').then(r=>{if(r.workspace?.profiles?.default){app.restoreWorkspace(r.workspace);if(r.workspace.settings)setSettings({...defaults,...r.workspace.settings});} setActive(r.activeProfile);setEnabled(r.enabled);}).catch(e=>setStatus(e.message));
    api('apps').then(r=>setApps(r.apps)).catch(()=>{});
    const timer=setInterval(()=>{api('studio').then(r=>{setActive(r.activeProfile);setEnabled(r.enabled);}).catch(()=>{});if(!document.documentElement.classList.contains('compact-launcher'))api('pending-photos').then(r=>{if(r.photos){setPendingPhotos(r);setTab('Photos');}}).catch(()=>{});},2000);
    const navigate=e=>setTab(e.detail || 'Launcher'); window.addEventListener('studio-tab',navigate);
    return ()=>{clearInterval(timer);window.removeEventListener('studio-tab',navigate);};
  },[]);
  const run=async fn=>{try{await fn();}catch(e){setStatus(e.message);}};
  const profile=app.profiles[app.profileId];
  const workspace=()=>({version:1,profiles:Object.fromEntries(Object.entries(app.profiles).map(([id,p])=>[id,{...p,items:JSON.parse(generateJSON(p.items))}])),settings});
  const save=()=>run(async()=>{await api('studio',workspace());setStatus(enabled?'Applied to Touch Bar · saved on this Mac':'Saved on this Mac · custom Touch Bar is off');});
  const toggleTouchBar=()=>run(async()=>{
    setToggling(true);
    try {const result=await api('touchbar',{enabled:!enabled});setEnabled(result.enabled);setStatus(result.enabled?'Custom Touch Bar on':'Custom Touch Bar off · macOS controls restored');}
    finally {setToggling(false);}
  });
  useEffect(()=>{const listener=()=>save();window.addEventListener('studio-save',listener);return ()=>window.removeEventListener('studio-save',listener);});
  const chooseProfile=async()=>{
    const r=await api('choose?kind=app');if(!r.cancelled){setName(r.name);setBundle(r.bundleId||'');}
  };
  const addProfile=()=>{
    if(!name.trim()||!bundle.trim())return;
    if(Object.values(app.profiles).some(p=>p.bundleId===bundle.trim())){setStatus('A profile already exists for this app.');return;}
    const id=crypto.randomUUID();
    const copy=JSON.parse(JSON.stringify(app.profiles.default.items));
    app.setProfiles({...app.profiles,[id]:{id,name:name.trim(),bundleId:bundle.trim(),enabled:true,items:copy}});
    setName('');setBundle('');setStatus('Profile created from Default. Select it to edit.');
  };
  const addTile=kind=>run(async()=>{
    const r=await api('choose?kind='+kind);if(r.cancelled)return;
    setSettings({...settings,tiles:[...settings.tiles,{id:crypto.randomUUID(),name:r.name,path:r.path,color:settings.accent,hidden:false,kind}]});
  });
  const updateTile=(id,patch)=>setSettings({...settings,tiles:settings.tiles.map(t=>t.id===id?{...t,...patch}:t)});
  return <div className="studio-shell" style={{'--studio-accent':settings.accent,'--studio-bg':settings.background,backgroundImage:settings.image?`linear-gradient(#101018cc,#101018ee),url(${settings.image})`:undefined}} data-motion={settings.motion}>
    <header className="studio-header"><div><strong>Touch Bar Studio</strong><small>Your Mac, within reach.</small></div><nav>{['Launcher','Studio','Photos','Appearance'].map(t=><button key={t} className={tab===t?'chosen':''} onClick={()=>setTab(t)}>{t}</button>)}</nav><button className="runtime-toggle" aria-pressed={enabled===true} disabled={!native||enabled===null||toggling} onClick={toggleTouchBar}>{enabled===null?'Checking Touch Bar…':enabled?'Touch Bar: On':'Touch Bar: Off'}</button><button className="primary" onClick={save}>Apply & Save</button></header>
    <div className="studio-status" role="status">{status}<span>Touch Bar: {enabled===false?'Off (macOS controls)':app.profiles[active]?.name || 'Default'}</span></div>
    {tab==='Studio'&&<>
      <div className="profile-strip"><label>Editing <select value={app.profileId} onChange={e=>app.switchProfile(e.target.value)}>{Object.entries(app.profiles).map(([id,p])=><option key={id} value={id}>{p.name}{p.enabled===false?' (disabled)':''}</option>)}</select></label>
      {app.profileId!=='default'&&<><input aria-label="Profile name" value={profile.name} onChange={e=>app.setProfiles({...app.profiles,[app.profileId]:{...profile,name:e.target.value}})}/><label><input type="checkbox" checked={profile.enabled} onChange={e=>app.setProfiles({...app.profiles,[app.profileId]:{...profile,enabled:e.target.checked}})}/>Enabled</label><button onClick={()=>{const id=app.profileId;app.switchProfile('default');const p={...app.profiles};delete p[id];app.setProfiles(p);}}>Delete profile</button></>}
      <button onClick={()=>download('touchbar-workspace.json',workspace())}>Export workspace</button><button onClick={()=>importRef.current.click()}>Import workspace</button>
      <input ref={importRef} hidden type="file" accept=".json" onChange={e=>run(async()=>{const file=e.target.files[0];if(!file)return;const w=JSON.parse(await file.text());if(w.version!==1||!w.profiles?.default||Object.values(w.profiles).some(p=>!Array.isArray(p.items)))throw Error('Expected a version 1 workspace with a Default profile.');app.restoreWorkspace(w);if(w.settings)setSettings({...defaults,...w.settings});setStatus('Workspace imported locally. Apply & Save to activate.');e.target.value='';})}/>
      </div>
      <details className="profile-add"><summary>Add an app profile</summary><div className="inline"><button onClick={()=>run(chooseProfile)}>Choose installed app…</button><select aria-label="Installed app" value="" onChange={e=>{const a=apps.find(a=>a.bundleId===e.target.value);if(a){setName(a.name);setBundle(a.bundleId);}}}><option value="">Installed apps…</option>{apps.map(a=><option key={a.bundleId} value={a.bundleId}>{a.name}</option>)}</select><input placeholder="Profile name" value={name} onChange={e=>setName(e.target.value)}/><input placeholder="Bundle ID, e.g. com.apple.finder" value={bundle} onChange={e=>setBundle(e.target.value)}/><button disabled={!name.trim()||!bundle.trim()} onClick={addProfile}>Duplicate Default</button></div></details>
      <div className="submenu-strip"><button disabled={!app.groupPath.length} onClick={app.leaveGroup}>‹ Back</button><span>{profile.name} root{app.groupNames.map((n,i)=><span key={i}> / {n}</span>)}</span>{app.items.filter(i=>i.type==='group').map(i=><button key={i.id} onClick={()=>app.enterGroup(i.id)}>Open {i.title||'Submenu'} ›</button>)}{app.selectedItemId&&<select aria-label="Move selected control" value="" onChange={e=>app.moveItem(app.selectedItemId,e.target.value==='root'?null:e.target.value)}><option value="">Move selected to…</option><option value="root">Root layout</option>{app.items.filter(i=>i.type==='group'&&i.id!==app.selectedItemId).map(i=><option key={i.id} value={i.id}>{i.title||'Submenu'}</option>)}</select>}</div>
      <div className="editor-host"><AppContent/></div><div className="script-note">Script controls are preserved for export but disabled in the runtime. Apply & Save activates complete profiles.</div>
    </>}
    {tab==='Launcher'&&<main className="workspace-page"><div className="page-heading"><div><p className="eyebrow">MAKE SPACE FOR YOUR WORK</p><h1>Everything, one touch away.</h1><p>Apps and folders for whatever you’re working on.</p></div><div><button onClick={()=>addTile('app')}>+ App</button> <button onClick={()=>addTile('folder')}>+ Folder</button></div></div>
      {!settings.tiles.length&&<div className="empty-card"><h2>Build your launchpad</h2><p>Add an app or folder above. Click a tile to open it.</p><button onClick={()=>addTile('app')}>Choose your first app</button></div>}
      <div className="tile-grid">{settings.tiles.filter(t=>!t.hidden).map(t=><button className="launch-tile" key={t.id} style={{borderColor:t.color}} onClick={()=>run(async()=>{await api('open?path='+encodeURIComponent(t.path));})}><span style={{color:t.color}}>{t.kind==='folder'?'▰':'◈'}</span><strong>{t.name}</strong><small>{t.kind==='folder'?'Folder':'Application'}</small></button>)}</div>
      <details className="tile-manager"><summary>Edit tiles</summary>{settings.tiles.map((t,i)=><div className="tile-row" key={t.id}><input aria-label="Tile name" value={t.name} onChange={e=>updateTile(t.id,{name:e.target.value})}/><input type="color" aria-label="Tile color" value={t.color} onChange={e=>updateTile(t.id,{color:e.target.value})}/><label><input type="checkbox" checked={t.hidden} onChange={e=>updateTile(t.id,{hidden:e.target.checked})}/>Hidden</label><button disabled={i===0} onClick={()=>{const tiles=[...settings.tiles];[tiles[i-1],tiles[i]]=[tiles[i],tiles[i-1]];setSettings({...settings,tiles});}}>←</button><button disabled={i===settings.tiles.length-1} onClick={()=>{const tiles=[...settings.tiles];[tiles[i+1],tiles[i]]=[tiles[i],tiles[i+1]];setSettings({...settings,tiles});}}>→</button><button onClick={()=>setSettings({...settings,tiles:settings.tiles.filter(x=>x.id!==t.id)})}>Remove</button></div>)}</details>
    </main>}
    {tab==='Photos'&&<Photos run={run} initial={pendingPhotos}/>}
    {tab==='Appearance'&&<main className="workspace-page appearance"><p className="eyebrow">MAKE IT YOURS</p><h1>A quieter kind of workspace.</h1><label>Accent color<input type="color" value={settings.accent} onChange={e=>setSettings({...settings,accent:e.target.value})}/></label><label>Background<input type="color" value={settings.background} onChange={e=>setSettings({...settings,background:e.target.value})}/></label><label>Motion<select value={settings.motion} onChange={e=>setSettings({...settings,motion:e.target.value})}><option value="off">Off</option><option value="subtle">Subtle fade</option></select></label><p>Reduced motion follows your Mac’s accessibility setting.</p><button onClick={()=>run(async()=>{const r=await api('choose?kind=image');if(r.image)setSettings({...settings,image:r.image});})}>Choose background image…</button> <button onClick={()=>setSettings({...settings,image:null})}>Clear image</button><hr/><label>Launcher shortcut<select value={settings.shortcut||"controlOption"} onChange={e=>setSettings({...settings,shortcut:e.target.value})}><option value="controlOption">Control + Option + Space</option><option value="commandShift">Command + Shift + Space</option></select></label><p>Open the compact launcher from the menu bar or your selected shortcut.</p><p>Preview changes here, then use Apply & Save to keep them across launches.</p></main>}
  </div>;
}
function Photos({run,initial}) {
 const [photos,setPhotos]=useState(initial?.photos||[]),[folder,setFolder]=useState(initial?.folder||''),[query,setQuery]=useState(''),[type,setType]=useState(''),[ratio,setRatio]=useState(''),[date,setDate]=useState(''),[size,setSize]=useState(180),[selected,setSelected]=useState(null),[loading,setLoading]=useState(false),[minWidth,setMinWidth]=useState(''),[minHeight,setMinHeight]=useState('');
 useEffect(()=>{if(initial?.photos){setPhotos(initial.photos);setFolder(initial.folder);}},[initial]);
 const choose=()=>run(async()=>{const r=await api('choose?kind=folder');if(r.cancelled)return;setLoading(true);try{const p=await api('photos?folder='+encodeURIComponent(r.path));setPhotos(p.photos);setFolder(r.path);setSelected(null);}finally{setLoading(false);}});
 const visible=photos.filter(p=>(!minWidth||p.width>=+minWidth)&&(!minHeight||p.height>=+minHeight)&&p.name.toLowerCase().includes(query.toLowerCase())&&(!type||p.type===type)&&(!date||p.date.slice(0,10)>=date)&&(!ratio||(ratio==='landscape'?p.width>p.height:ratio==='portrait'?p.height>p.width:p.height===p.width)));
 return <main className="workspace-page"><div className="page-heading"><div><p className="eyebrow">PHOTO WORKSPACE</p><h1>Your photos. Room to explore.</h1><p>{folder||'Choose a folder to browse. Originals stay untouched.'}</p></div><button onClick={choose}>Choose folder…</button></div><div className="photo-filters"><input placeholder="Filter filename…" value={query} onChange={e=>setQuery(e.target.value)}/><select value={type} onChange={e=>setType(e.target.value)}><option value="">All file types</option>{[...new Set(photos.map(p=>p.type))].map(t=><option key={t}>{t}</option>)}</select><select value={ratio} onChange={e=>setRatio(e.target.value)}><option value="">All shapes</option><option value="landscape">Landscape</option><option value="portrait">Portrait</option><option value="square">Square</option></select><input type="number" min="0" placeholder="Min width px" aria-label="Minimum pixel width" value={minWidth} onChange={e=>setMinWidth(e.target.value)}/><input type="number" min="0" placeholder="Min height px" aria-label="Minimum pixel height" value={minHeight} onChange={e=>setMinHeight(e.target.value)}/><label>Modified since <input type="date" value={date} onChange={e=>setDate(e.target.value)}/></label><label>Size<input type="range" min="100" max="300" value={size} onChange={e=>setSize(+e.target.value)}/></label><span>{visible.length} photos</span></div>{loading&&<p>Reading photo metadata…</p>}<div className="photo-layout"><div className="photo-grid" style={{gridTemplateColumns:`repeat(auto-fill,minmax(${size}px,1fr))`}}>{visible.map(p=><button className="photo" key={p.id} onClick={()=>setSelected(p)}><img loading="lazy" src={'/api/thumbnail?id='+p.id} alt={p.name}/><span>{p.name}</span></button>)}</div>{selected&&<aside className="photo-inspector"><h2>{selected.name}</h2><p>{selected.type.toUpperCase()}</p><p>{selected.width} × {selected.height} px</p><p>Ratio {(selected.width/selected.height).toFixed(3)}</p><p>Modified {new Date(selected.date).toLocaleString()}</p></aside>}</div></main>;
}
