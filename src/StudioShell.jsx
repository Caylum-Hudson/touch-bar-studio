import PackBrowser from './components/Palette/PackBrowser';
import { useState, useEffect, useRef } from 'react';
import { useApp } from './context/AppContext';
import { RuntimePermissionsProvider } from './context/RuntimePermissions';
import { createElement } from './data/elementDefinitions';
import { getPermissionLabel } from './data/controlAvailability';
import { AppContent } from './App';
import { generateJSON } from './utils/jsonGenerator';
import { workspaceImportError } from './utils/workspaceValidation';
import { themeTokens } from './utils/themeTokens.js';
import './StudioShell.css';
import './StudioTheme.css';
import appMetadata from '../package.json';
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
const defaults = {accent:'#a78bfa',background:'#14151d',motion:'off',tiles:[],keepControlStrip:false,previewScalePercent:100,useResolveNativeColorPage:true};
const RESOLVE_BUNDLE_ID='com.blackmagic-design.DaVinciResolve';
const resolvePages=[['media','Media'],['photo','Photo'],['cut','Cut'],['edit','Edit'],['fusion','Fusion'],['color','Color'],['fairlight','Fairlight'],['deliver','Deliver']];
const resolveEditorPages=[['fallback','Profile fallback'],...resolvePages];
const createResolveEditLayout=()=>['resolvePlayReverse','resolveStop','resolvePlayForward','resolveFrameBack','resolveFrameForward','resolvePreviousEdit','resolveNextEdit','resolveTimelineStart','resolveTimelineEnd','resolveMarkIn','resolveMarkOut','resolveToggleSnapping'].map(key=>createElement(key));
const createResolveColorLayout=()=>[
  ['+Serial',1,['option']],['+Parallel',35,['option']],['+Layer',37,['option']],['+Outside',31,['option']],
  ['Node ⏻',2,['command']],['All ⏻',2,['option']],['← Node',41,['option','shift']],['Node →',39,['option','shift']],
].map(([title,keycode,modifiers])=>createElement('staticButton',{title,matchAppId:'^com\\.blackmagic-design\\.DaVinciResolve$',actions:[{trigger:'singleTap',action:'keyPress',keycode,modifiers}]}));
export default function StudioShell() {
  const app = useApp();
  const [tab,setTab] = useState(document.documentElement.classList.contains('compact-launcher')?'Launcher':'Studio');
  const studioTab = tab === 'Studio';
  const [settings,setSettings] = useState(()=> {try{return {...defaults,...JSON.parse(localStorage.getItem('studio-settings'))};}catch{return defaults;}});
  const [status,setStatus] = useState('Ready — changes are saved locally');
  const [workspaceLoadError,setWorkspaceLoadError] = useState('');
  const [workspaceReplacementPrepared,setWorkspaceReplacementPrepared] = useState(false);
  const workspaceReplacementPreparedRef=useRef(workspaceReplacementPrepared);
  workspaceReplacementPreparedRef.current=workspaceReplacementPrepared;
  const [active,setActive] = useState('default');
  const [activeResolvePage,setActiveResolvePage] = useState(null);
  const [resolvePageOverride,setResolvePageOverride] = useState(null);
  const [resolvePageDetection,setResolvePageDetection] = useState('inactive');
  const [activeResolvePageFallback,setActiveResolvePageFallback] = useState(false);
  const [nativeResolveColorPageActive,setNativeResolveColorPageActive] = useState(false);
  const [enabled,setEnabled] = useState(null);
  const [toggling,setToggling] = useState(false);
  const [keyboardAccess,setKeyboardAccess] = useState(null);
  const [eventPostingAllowed,setEventPostingAllowed] = useState(null);
  const [controlStripBusy,setControlStripBusy] = useState(false);
  const [controlStripError,setControlStripError] = useState('');
  const [layoutCapacity,setLayoutCapacity] = useState(null);
  const [systemMonitorPreviews,setSystemMonitorPreviews] = useState([]);
  const [activeStudioGroupPath,setActiveStudioGroupPath] = useState([]);
  const controlStripBusyRef=useRef(false);
  const nativeColorPreferenceDirtyRef=useRef(false);
  const nativeColorPreferenceRevisionRef=useRef(0);
  const studioRequestRef=useRef(null);
  const refreshStudioRef=useRef(null);
  const initialStudioLoadedRef=useRef(false);
  const studioWorkspaceFetchedRef=useRef(false);
  useEffect(()=>{
    if(enabled===null)return;
    setStatus(previous=>previous.startsWith('Custom Touch Bar')?(enabled?'Custom Touch Bar on':'Custom Touch Bar off · macOS controls restored'):previous);
  },[enabled]);
  useEffect(()=>{
    if(!studioTab||status==='Ready — changes are saved locally')return;
    const timer=setTimeout(()=>{
      if(status==='Applied to Touch Bar · saved on this Mac'||status==='Saved on this Mac · custom Touch Bar is off'||status.startsWith('macOS Control Strip '))setStatus('Ready — changes are saved locally');
    },3000);
    return ()=>clearTimeout(timer);
  },[status,tab,studioTab]);
  const [pendingPhotos,setPendingPhotos] = useState(null);
  const [apps,setApps] = useState([]);
  const [profileIcon,setProfileIcon] = useState(null);
  useEffect(()=>{ let current=true; setProfileIcon(null); const id=app.profiles[app.profileId]?.bundleId; if(native && id) api(`profile-icon?bundleId=${encodeURIComponent(id)}`).then(result=>{if(current)setProfileIcon(result.iconData || null);}).catch(()=>{}); return ()=>{current=false;}; },[app.profileId, app.profiles, native]);
  const [name,setName] = useState('');
  const [bundle,setBundle] = useState('');
  const [profileAddOpen,setProfileAddOpen] = useState(false);
  const profileNameRef=useRef(null);
  const importRef=useRef(null);
  useEffect(()=>{if(profileAddOpen)profileNameRef.current?.focus();},[profileAddOpen]);
  useEffect(()=>{localStorage.setItem('studio-settings',JSON.stringify(settings));},[settings]);
  useEffect(()=>{
    if(!native)return;
    const refreshStudio=()=>{
      if(studioRequestRef.current)return studioRequestRef.current;
      const includeWorkspace=!studioWorkspaceFetchedRef.current;
      const nativeColorPreferenceRevision=nativeColorPreferenceRevisionRef.current;
      const request=api(includeWorkspace?'studio':'studio?statusOnly=1').then(r=>{
        if(includeWorkspace)studioWorkspaceFetchedRef.current=true;
        const loadError=typeof r.workspaceLoadError==='string'?r.workspaceLoadError:'';
        setWorkspaceLoadError(loadError);
        if(!loadError)setWorkspaceReplacementPrepared(false);
        if(loadError&&!workspaceReplacementPreparedRef.current)setStatus(`Saved workspace needs attention. ${loadError} Import a backup before replacing it.`);
        if(!initialStudioLoadedRef.current&&r.workspace?.profiles?.default){app.restoreWorkspace(r.workspace);if(r.workspace.settings)setSettings(s=>({...s,...defaults,...r.workspace.settings}));initialStudioLoadedRef.current=true;}
        setLayoutCapacity(r.layoutCapacity || null);
        setSystemMonitorPreviews(Array.isArray(r.systemMonitorPreviews)?r.systemMonitorPreviews:[]);
        setActiveStudioGroupPath(Array.isArray(r.studioGroupPath)?r.studioGroupPath:[]);
        setActive(r.activeProfile);setActiveResolvePage(r.activeResolvePage||null);setResolvePageOverride(r.resolvePageOverride||null);setResolvePageDetection(r.resolvePageDetection||'inactive');setActiveResolvePageFallback(r.activeResolvePageFallback===true);setNativeResolveColorPageActive(r.nativeResolveColorPageActive===true);setEnabled(r.enabled);setKeyboardAccess(r.accessibilityTrusted ?? r.keyboardAccess ?? null);setEventPostingAllowed(r.eventPostingAllowed ?? null);
        const effective=r.keepControlStrip ?? r.workspace?.settings?.keepControlStrip;
        if(typeof effective==='boolean'&&!controlStripBusyRef.current)setSettings(s=>s.keepControlStrip===effective?s:{...s,keepControlStrip:effective});
        const nativeColor=r.useResolveNativeColorPage ?? r.workspace?.settings?.useResolveNativeColorPage;
        if(typeof nativeColor==='boolean'&&!nativeColorPreferenceDirtyRef.current&&nativeColorPreferenceRevision===nativeColorPreferenceRevisionRef.current)setSettings(s=>s.useResolveNativeColorPage===nativeColor?s:{...s,useResolveNativeColorPage:nativeColor});
        return r;
      }).catch(e=>{setStatus(e.message);throw e;}).finally(()=>{studioRequestRef.current=null;});
      studioRequestRef.current=request;
      return request;
    };
    refreshStudioRef.current=refreshStudio;
    refreshStudio().catch(()=>{});
    api('apps').then(r=>setApps(r.apps)).catch(()=>{});
    const refreshOnFocus=()=>refreshStudio().catch(()=>{});
    const refreshWhenVisible=()=>{if(document.visibilityState==='visible')refreshOnFocus();};
    window.addEventListener('focus',refreshOnFocus);
    document.addEventListener('visibilitychange',refreshWhenVisible);
    const timer=setInterval(()=>{refreshStudio().catch(()=>{});if(!document.documentElement.classList.contains('compact-launcher'))api('pending-photos').then(r=>{if(r.photos){setPendingPhotos(r);setTab('Photos');}}).catch(e=>setStatus(`Photo import failed: ${e.message}`));},2000);
    const navigate=e=>setTab(e.detail || 'Launcher'); window.addEventListener('studio-tab',navigate);
    return ()=>{clearInterval(timer);window.removeEventListener('studio-tab',navigate);window.removeEventListener('focus',refreshOnFocus);document.removeEventListener('visibilitychange',refreshWhenVisible);refreshStudioRef.current=null;};
  },[]);
  const run=async fn=>{try{await fn();}catch(e){setStatus(e.message);}};
  const profile=app.profiles[app.profileId];
  const activeRuntimeProfile=app.profiles[active];
  const activeRuntimePageLabel=resolvePages.find(([id])=>id===activeResolvePage)?.[1];
  const activeRuntimePageStatus=nativeResolveColorPageActive?'Native Color page':activeRuntimeProfile?.bundleId===RESOLVE_BUNDLE_ID&&!activeRuntimePageLabel
    ? resolvePageDetection==='accessibility-required'?'Page unknown · Accessibility required':'Page unknown · profile fallback'
    : activeRuntimePageLabel?`Page: ${activeRuntimePageLabel} (${resolvePageOverride?'Manual':'Auto'}${activeResolvePageFallback?' · profile fallback':''})`:null;
  const resolveProfile=Object.entries(app.profiles).find(([,p])=>p.bundleId===RESOLVE_BUNDLE_ID);
  const workspace=()=>({version:1,profiles:Object.fromEntries(Object.entries(app.profiles).map(([id,p])=>[id,{...p,items:JSON.parse(generateJSON(p.items)),...(p.resolvePageLayouts?{resolvePageLayouts:Object.fromEntries(Object.entries(p.resolvePageLayouts).map(([page,items])=>[page,JSON.parse(generateJSON(items))]))}:{})}])),settings});
  const save=()=>run(async()=>{
    let replaceUnreadable=false;
    if(workspaceLoadError){
      if(workspaceReplacementPrepared)replaceUnreadable=true;
      else {
        if(!window.confirm('The saved workspace could not be loaded. The original file will be preserved as an unreadable backup. Save this editor workspace over it? Import a backup first if you want to restore an earlier layout.'))return;
        replaceUnreadable=true;
      }
    }
    const result=await api('studio',{workspace:workspace(),replaceUnreadable});
    setWorkspaceLoadError('');
    setWorkspaceReplacementPrepared(false);
    nativeColorPreferenceDirtyRef.current=false;
    nativeColorPreferenceRevisionRef.current+=1;
    setNativeResolveColorPageActive(result.nativeResolveColorPageActive===true);
    if(typeof result.keepControlStrip==='boolean')setSettings(s=>({...s,keepControlStrip:result.keepControlStrip}));
    if(typeof result.useResolveNativeColorPage==='boolean')setSettings(s=>({...s,useResolveNativeColorPage:result.useResolveNativeColorPage}));
    setStatus(result.nativeResolveColorPageActive?'Native Color page is using Resolve controls':enabled?'Applied to Touch Bar · saved on this Mac':'Saved on this Mac · custom Touch Bar is off');
  });
  const updateControlStrip=async value=>{
    if(!native||controlStripBusyRef.current)return;
    const previous=settings.keepControlStrip===true;
    controlStripBusyRef.current=true;setControlStripBusy(true);setControlStripError('');
    setSettings(s=>({...s,keepControlStrip:value}));
    try{
      const result=await api('control-strip',{enabled:value});
      const effective=typeof result.keepControlStrip==='boolean'?result.keepControlStrip:value;
      setSettings(s=>({...s,keepControlStrip:effective}));
      setStatus(effective?'macOS Control Strip kept available':'macOS Control Strip restored to its previous setting');
    }catch(error){
      setSettings(s=>({...s,keepControlStrip:previous}));setControlStripError(error.message);setStatus('Could not update the macOS Control Strip setting.');
    }finally{controlStripBusyRef.current=false;setControlStripBusy(false);}
  };
  const recheckAccessibility=()=>{refreshStudioRef.current?.().catch(e=>setControlStripError(e.message));};
  const updateRuntimeResolvePage=page=>run(async()=>{await api('resolve-page',{page});setResolvePageOverride(page==='auto'?null:page);setStatus(page==='auto'?'Resolve page selection set to automatic detection.':'Touch Bar Resolve page set manually.');});
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
    app.switchProfile(id);
    setName('');setBundle('');setProfileAddOpen(false);setStatus('App profile created from Default. Apply & Save to activate.');
  };
  const setupResolvePages=()=>{
    let targetId=resolveProfile?.[0];
    let profiles={...app.profiles};
    if(!targetId){
      targetId=crypto.randomUUID();
      profiles[targetId]={id:targetId,name:'DaVinci Resolve',bundleId:RESOLVE_BUNDLE_ID,enabled:true,items:JSON.parse(JSON.stringify(app.profiles.default.items)),resolvePageLayouts:{edit:createResolveEditLayout(),color:createResolveColorLayout()}};
      app.setProfiles(profiles);
      app.switchProfile(targetId);
      app.switchResolvePage('edit');
      setStatus('Resolve profile created with Edit and Color layouts. Apply & Save to activate.');
      return;
    }
    const existing=profiles[targetId];
    const missingEdit=!existing.resolvePageLayouts?.edit;
    const missingColor=!existing.resolvePageLayouts?.color;
    if(missingEdit||missingColor){
      profiles[targetId]={...existing,resolvePageLayouts:{...(existing.resolvePageLayouts||{}),...(missingEdit?{edit:createResolveEditLayout()}:{}),...(missingColor?{color:createResolveColorLayout()}:{})}};
      app.setProfiles(profiles);
      app.switchProfile(targetId);
      app.switchResolvePage('edit');
      setStatus('Missing Edit and Color layouts added without changing existing layouts. Apply & Save to activate.');
    } else {
      app.switchProfile(targetId);
      app.switchResolvePage('fallback');
    }
  };
  const createResolvePageLayout=pageId=>{
    const base=app.profiles[app.profileId]?.items||app.profiles.default.items;
    app.createResolvePage(pageId,JSON.parse(JSON.stringify(base)));
    setStatus(`${resolvePages.find(([id])=>id===pageId)?.[1]||'Resolve'} layout copied from the profile. Apply & Save to activate.`);
  };
  const addTile=kind=>run(async()=>{
    const r=await api('choose?kind='+kind);if(r.cancelled)return;
    setSettings({...settings,tiles:[...settings.tiles,{id:crypto.randomUUID(),name:r.name,path:r.path,color:settings.accent,hidden:false,kind}]});
  });
  const updateTile=(id,patch)=>setSettings({...settings,tiles:settings.tiles.map(t=>t.id===id?{...t,...patch}:t)});
  return <div className="studio-shell" style={{...themeTokens(settings.background,settings.accent),backgroundImage:settings.image?`linear-gradient(#0005,#0007),url(${settings.image})`:undefined}} data-motion={settings.motion}>
    <header className="studio-header"><div><strong>Touch Bar Studio</strong><small>v{appMetadata.version} · Your Mac, within reach.</small></div><nav>{['Studio','Browse','Appearance','Settings'].map(t=><button key={t} className={tab===t?'chosen':''} onClick={()=>setTab(t)}>{t}</button>)}</nav><button className="runtime-toggle" aria-pressed={enabled===true} disabled={!native||enabled===null||toggling} onClick={toggleTouchBar}>{enabled===null?'Checking Touch Bar…':enabled?'Touch Bar: On':'Touch Bar: Off'}</button><button className="primary" onClick={save}>Apply & Save</button></header>
    {(tab!=='Browse' && (!studioTab||status!=='Ready — changes are saved locally'))&&<div className={`studio-status ${studioTab?'studio-feedback':''}`} role="status">{status}<span>Touch Bar: {enabled===false?'Off (macOS controls)':app.profiles[active]?.name || 'Default'}</span></div>}
    {native && keyboardAccess===false && <div className="permission-notice" role="status"><span>macOS has not authorized keyboard control for this running app. Accessibility controls keyboard and media access; Full Disk Access is separate.</span><div><button onClick={()=>run(async()=>{await api('keyboard-permission',{});})}>Review Accessibility settings</button> <button onClick={recheckAccessibility}>Recheck status</button></div></div>}
    {native&&workspaceLoadError&&<div className="permission-error" role="alert">{workspaceLoadError} {workspaceReplacementPrepared?'A workspace has been imported. Apply & Save to replace the unreadable file; its original bytes and prior backup will be kept.':'The original file is preserved. Import a workspace backup before saving a replacement.'}</div>}
    {native&&controlStripError&&<div className="permission-error" role="alert">{controlStripError}</div>}
    {studioTab&&<>
      <details className="compact-profile"><summary title="Choose the profile you are editing" aria-label={`Editing ${profile?.name || "Default bar"}; choose profile`}><span className="profile-app-icon">{profile?.bundleId ? (profileIcon ? <img src={profileIcon} alt=""/> : (profile.name || "App").slice(0,1).toUpperCase()) : "⌘"}</span></summary><div className="profile-toolbar">
        <label className="profile-editor-select"><span>Editing</span><select aria-label="Editing profile" value={app.profileId} onChange={e=>app.switchProfile(e.target.value)}>{Object.entries(app.profiles).map(([id,p])=><option key={id} value={id}>{id==='default'?'Default bar':p.name}{p.enabled===false?' (disabled)':''}</option>)}</select></label>
        {profile?.bundleId===RESOLVE_BUNDLE_ID&&<label className="profile-editor-select resolve-page-select"><span>Editing Resolve page</span><select aria-label="Editing Resolve page" value={app.resolvePageId} onChange={e=>app.switchResolvePage(e.target.value)}>{resolveEditorPages.map(([id,label])=><option key={id} value={id}>{label}{id!=='fallback'&&!profile.resolvePageLayouts?.[id]?' · profile fallback':''}</option>)}</select></label>}
        <div className="profile-runtime" aria-live="polite"><small>Active on Touch Bar</small><strong>{enabled===null?'Checking…':enabled?`${activeRuntimeProfile?.name||'Default bar'}${activeRuntimePageStatus?` · ${activeRuntimePageStatus}`:''}`:'Off'}</strong></div>
        {resolveProfile&&<label className="profile-editor-select resolve-runtime-page-select"><span>Touch Bar page</span><select aria-label="Touch Bar Resolve page" value={resolvePageOverride||'auto'} disabled={!native} onChange={e=>updateRuntimeResolvePage(e.target.value)}><option value="auto">Auto detect</option>{resolvePages.map(([id,label])=><option key={id} value={id}>{label} · manual</option>)}</select></label>}
        <button type="button" className="profile-add-action" aria-expanded={profileAddOpen} onClick={()=>setProfileAddOpen(open=>!open)}>{profileAddOpen?'Close':'＋ Add app profile'}</button>
        {profile?.bundleId!==RESOLVE_BUNDLE_ID&&<button type="button" className="profile-add-action resolve-setup-action" onClick={setupResolvePages}>{resolveProfile?'Set up Resolve pages':'＋ Resolve page layouts'}</button>}
      </div>
      {profileAddOpen&&<div className="profile-add-form"><p>Starts with a copy of Default.</p><div className="inline"><button type="button" onClick={()=>run(chooseProfile)}>Choose installed app…</button><select aria-label="Installed app" value="" onChange={e=>{const a=apps.find(a=>a.bundleId===e.target.value);if(a){setName(a.name);setBundle(a.bundleId);}}}><option value="">Installed apps…</option>{apps.map(a=><option key={a.bundleId} value={a.bundleId}>{a.name}</option>)}</select><input ref={profileNameRef} aria-label="Profile name" placeholder="Profile name" value={name} onChange={e=>setName(e.target.value)}/><input aria-label="App bundle ID" placeholder="Bundle ID, e.g. com.apple.finder" value={bundle} onChange={e=>setBundle(e.target.value)}/><button disabled={!name.trim()||!bundle.trim()} onClick={addProfile}>Create app profile</button></div></div>}
      <details className="studio-options"><summary>Studio options <span>{profile?.name||'Default'} profile</span></summary><div className="studio-options-content"><div className="profile-strip">
      {app.profileId!=='default'&&<><input aria-label="Profile name" value={profile.name} onChange={e=>app.setProfiles({...app.profiles,[app.profileId]:{...profile,name:e.target.value}})}/><label><input type="checkbox" checked={profile.enabled} onChange={e=>app.setProfiles({...app.profiles,[app.profileId]:{...profile,enabled:e.target.checked}})}/>Enabled</label><button onClick={()=>{const id=app.profileId;app.switchProfile('default');const p={...app.profiles};delete p[id];app.setProfiles(p);}}>Delete profile</button></>}
      </div></div></details>
      {resolveProfile&&<label className="resolve-native-color-toggle"><span><strong>Use Resolve’s native Touch Bar on Color</strong><small>When DaVinci Resolve is on its detected Color page, let Resolve show its own controls. The detected page takes priority over the manual Touch Bar page while this is on. Your custom Studio layout returns on Edit and other pages.</small></span><input type="checkbox" checked={settings.useResolveNativeColorPage!==false} onChange={e=>{nativeColorPreferenceDirtyRef.current=true;nativeColorPreferenceRevisionRef.current+=1;setSettings(s=>({...s,useResolveNativeColorPage:e.target.checked}));}}/></label>}
      </details>
      {resolveProfile&&nativeResolveColorPageActive&&<div className="resolve-native-preview" role="status">Resolve’s native Color controls are active; this editor shows the Studio layout you are editing.</div>}
      {app.groupPath.length>0&&<div className="submenu-strip"><button onClick={app.leaveGroup}>‹ Back</button><span>{profile?.name||'Default'}{app.groupNames.map((n,i)=><span key={i}> / {n}</span>)}</span>{app.selectedItemId&&<select aria-label="Move selected control" value="" onChange={e=>app.moveItem(app.selectedItemId,e.target.value==='root'?null:e.target.value)}><option value="">Move selected to…</option><option value="root">Root layout</option>{app.items.filter(i=>i.type==='group'&&i.id!==app.selectedItemId).map(i=><option key={i.id} value={i.id}>{i.title||'Submenu'}</option>)}</select>}</div>}
      {profile?.bundleId===RESOLVE_BUNDLE_ID&&!app.resolvePageReady&&app.resolvePageId!=='fallback'?<section className="resolve-page-empty"><h2>No {resolvePages.find(([id])=>id===app.resolvePageId)?.[1]} layout yet</h2><p>The Touch Bar uses the profile fallback layout for that page. Create a separate layout by copying the profile fallback; this will not change other pages.</p><button type="button" className="primary" onClick={()=>createResolvePageLayout(app.resolvePageId)}>Create layout from profile</button></section>:<div className="editor-host"><RuntimePermissionsProvider accessibilityAccess={keyboardAccess} eventPostingAllowed={eventPostingAllowed} native={native} keepControlStrip={settings.keepControlStrip===true} updateKeepControlStrip={updateControlStrip} controlStripBusy={controlStripBusy} layoutCapacity={layoutCapacity} systemMonitorPreviews={systemMonitorPreviews} activeStudioGroupPath={activeStudioGroupPath} activeRuntimeProfile={active} activeRuntimeResolvePage={activeResolvePageFallback?'fallback':activeResolvePage} activeRuntimeEnabled={enabled===true} previewScalePercent={settings.previewScalePercent ?? 100} updatePreviewScalePercent={value=>setSettings(current=>({...current,previewScalePercent:value}))}><AppContent/></RuntimePermissionsProvider></div>}
    </>}
    {tab==='Browse'&&<PackBrowser/>}
    {tab==='Launcher'&&<main className="workspace-page"><div className="page-heading"><div><p className="eyebrow">MAKE SPACE FOR YOUR WORK</p><h1>Everything, one touch away.</h1><p>Apps and folders for whatever you’re working on.</p></div><div><button onClick={()=>addTile('app')}>+ App</button> <button onClick={()=>addTile('folder')}>+ Folder</button></div></div>
      {!settings.tiles.length&&<div className="empty-card"><h2>Build your launchpad</h2><p>Add an app or folder above. Click a tile to open it.</p><button onClick={()=>addTile('app')}>Choose your first app</button></div>}
      <div className="tile-grid">{settings.tiles.filter(t=>!t.hidden).map(t=><button className="launch-tile" key={t.id} style={{borderColor:t.color}} onClick={()=>run(async()=>{await api('open?path='+encodeURIComponent(t.path));})}><span style={{color:t.color}}>{t.kind==='folder'?'▰':'◈'}</span><strong>{t.name}</strong><small>{t.kind==='folder'?'Folder':'Application'}</small></button>)}</div>
      <details className="tile-manager"><summary>Edit tiles</summary>{settings.tiles.map((t,i)=><div className="tile-row" key={t.id}><input aria-label="Tile name" value={t.name} onChange={e=>updateTile(t.id,{name:e.target.value})}/><input type="color" aria-label="Tile color" value={t.color} onChange={e=>updateTile(t.id,{color:e.target.value})}/><label><input type="checkbox" checked={t.hidden} onChange={e=>updateTile(t.id,{hidden:e.target.checked})}/>Hidden</label><button disabled={i===0} onClick={()=>{const tiles=[...settings.tiles];[tiles[i-1],tiles[i]]=[tiles[i],tiles[i-1]];setSettings({...settings,tiles});}}>←</button><button disabled={i===settings.tiles.length-1} onClick={()=>{const tiles=[...settings.tiles];[tiles[i+1],tiles[i]]=[tiles[i],tiles[i+1]];setSettings({...settings,tiles});}}>→</button><button onClick={()=>setSettings({...settings,tiles:settings.tiles.filter(x=>x.id!==t.id)})}>Remove</button></div>)}</details>
    </main>}
    {tab==='Photos'&&<Photos run={run} initial={pendingPhotos}/>}
    {tab==='Settings'&&<main className="workspace-page appearance"><h1>Settings</h1><h2>Workspace</h2><p>Import or export profiles and layouts.</p><button onClick={()=>download('touchbar-workspace.json',workspace())}>Export workspace</button> <button onClick={()=>importRef.current.click()}>Import workspace</button></main>}
      <input ref={importRef} hidden type="file" accept=".json" onChange={e=>run(async()=>{const input=e.target;const file=input.files[0];if(!file)return;try{const w=JSON.parse(await file.text());const error=workspaceImportError(w);if(error)throw Error(error);app.restoreWorkspace(w);if(w.settings){setSettings({...defaults,...w.settings});nativeColorPreferenceDirtyRef.current=true;nativeColorPreferenceRevisionRef.current+=1;}setWorkspaceReplacementPrepared(true);setStatus('Workspace imported locally. Apply & Save to activate.');}finally{input.value='';}})}/>
    {tab==='Appearance'&&<main className="workspace-page appearance"><p className="eyebrow">MAKE IT YOURS</p><h1>A quieter kind of workspace.</h1>{native&&<section className="permission-status-panel" aria-label="macOS input permissions"><div><strong>Accessibility</strong><span>{getPermissionLabel(keyboardAccess)}</span></div><div><strong>Keyboard event posting</strong><span>{getPermissionLabel(eventPostingAllowed)}</span></div><p>Live status reported by macOS. Recheck after reviewing System Settings.</p>{keyboardAccess===false&&<p>If this changed after a local app update, macOS may still be reporting the prior app authorization state.</p>}<button onClick={recheckAccessibility}>Recheck permissions</button></section>}<label>Accent color<input type="color" value={settings.accent} onChange={e=>setSettings({...settings,accent:e.target.value})}/></label><label>Background<input type="color" value={settings.background} onChange={e=>setSettings({...settings,background:e.target.value})}/></label><label>Motion<select value={settings.motion} onChange={e=>setSettings({...settings,motion:e.target.value})}><option value="off">Off</option><option value="subtle">Subtle fade</option></select></label><p>Reduced motion follows your Mac’s accessibility setting.</p><button onClick={()=>run(async()=>{const r=await api('choose?kind=image');if(r.image)setSettings({...settings,image:r.image});})}>Choose background image…</button> <button onClick={()=>setSettings({...settings,image:null})}>Clear image</button><hr/><label className="control-strip-toggle"><span><strong>Keep macOS Control Strip</strong><small>Keep Apple’s native controls beside your layout; use their arrow to expand or collapse.</small></span><input type="checkbox" checked={settings.keepControlStrip===true} disabled={!native||controlStripBusy} onChange={e=>updateControlStrip(e.target.checked)}/></label><p>The setting applies immediately and does not turn on the custom Touch Bar.{controlStripBusy?' Updating…':''}</p><label>Launcher shortcut<select value={settings.shortcut||"controlOption"} onChange={e=>setSettings({...settings,shortcut:e.target.value})}><option value="controlOption">Control + Option + Space</option><option value="commandShift">Command + Shift + Space</option></select></label><p>Open the compact launcher from the menu bar or your selected shortcut.</p><p>Preview changes here, then use Apply & Save to keep them across launches.</p></main>}
  </div>;
}
function Photos({run,initial}) {
 const [photos,setPhotos]=useState(initial?.photos||[]),[folder,setFolder]=useState(initial?.folder||''),[query,setQuery]=useState(''),[type,setType]=useState(''),[ratio,setRatio]=useState(''),[date,setDate]=useState(''),[size,setSize]=useState(180),[selected,setSelected]=useState(null),[loading,setLoading]=useState(false),[minWidth,setMinWidth]=useState(''),[minHeight,setMinHeight]=useState('');
 useEffect(()=>{if(initial?.photos){setPhotos(initial.photos);setFolder(initial.folder);}},[initial]);
 const choose=()=>run(async()=>{const r=await api('choose?kind=folder');if(r.cancelled)return;setLoading(true);try{const p=await api('photos?folder='+encodeURIComponent(r.path));setPhotos(p.photos);setFolder(r.path);setSelected(null);}finally{setLoading(false);}});
 const visible=photos.filter(p=>(!minWidth||p.width>=+minWidth)&&(!minHeight||p.height>=+minHeight)&&p.name.toLowerCase().includes(query.toLowerCase())&&(!type||p.type===type)&&(!date||p.date.slice(0,10)>=date)&&(!ratio||(ratio==='landscape'?p.width>p.height:ratio==='portrait'?p.height>p.width:p.height===p.width)));
 return <main className="workspace-page"><div className="page-heading"><div><p className="eyebrow">PHOTO WORKSPACE</p><h1>Your photos. Room to explore.</h1><p>{folder||'Choose a folder to browse. Originals stay untouched.'}</p></div><button onClick={choose}>Choose folder…</button></div><div className="photo-filters"><input placeholder="Filter filename…" value={query} onChange={e=>setQuery(e.target.value)}/><select value={type} onChange={e=>setType(e.target.value)}><option value="">All file types</option>{[...new Set(photos.map(p=>p.type))].map(t=><option key={t}>{t}</option>)}</select><select value={ratio} onChange={e=>setRatio(e.target.value)}><option value="">All shapes</option><option value="landscape">Landscape</option><option value="portrait">Portrait</option><option value="square">Square</option></select><input type="number" min="0" placeholder="Min width px" aria-label="Minimum pixel width" value={minWidth} onChange={e=>setMinWidth(e.target.value)}/><input type="number" min="0" placeholder="Min height px" aria-label="Minimum pixel height" value={minHeight} onChange={e=>setMinHeight(e.target.value)}/><label>Modified since <input type="date" value={date} onChange={e=>setDate(e.target.value)}/></label><label>Size<input type="range" min="100" max="300" value={size} onChange={e=>setSize(+e.target.value)}/></label><span>{visible.length} photos</span></div>{loading&&<p>Reading photo metadata…</p>}<div className="photo-layout"><div className="photo-grid" style={{gridTemplateColumns:`repeat(auto-fill,minmax(${size}px,1fr))`}}>{visible.map(p=><button className="photo" key={p.id} onClick={()=>setSelected(p)}><img loading="lazy" src={'/api/thumbnail?id='+p.id} alt={p.name}/><span>{p.name}</span></button>)}</div>{selected&&<aside className="photo-inspector"><h2>{selected.name}</h2><p>{selected.type.toUpperCase()}</p><p>{selected.width} × {selected.height} px</p><p>Ratio {(selected.width/selected.height).toFixed(3)}</p><p>Modified {new Date(selected.date).toLocaleString()}</p></aside>}</div></main>;
}
