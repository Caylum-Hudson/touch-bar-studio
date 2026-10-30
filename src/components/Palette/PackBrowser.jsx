import {useEffect, useState} from 'react';
import {controlPacks, normalizeControlPackPreferences} from '../../data/controlPacks';
import './Palette.css';

export default function PackBrowser() {
  const [query,setQuery] = useState('');
  const [sort,setSort] = useState('alphabetical');
  const [preferences,setPreferences] = useState(() => {
    try { return normalizeControlPackPreferences(JSON.parse(localStorage.getItem('mtmr-control-packs'))); }
    catch { return normalizeControlPackPreferences(null); }
  });
  useEffect(() => { localStorage.setItem('mtmr-control-packs', JSON.stringify(preferences)); }, [preferences]);
  const search = query.trim().toLowerCase();
  const packs = controlPacks.filter(pack => [pack.label,pack.description,...pack.controls.map(item=>item.label)].some(value=>value.toLowerCase().includes(search))).sort((a,b)=>{
    if (sort === 'most') return b.controls.length-a.controls.length || a.label.localeCompare(b.label);
    if (sort === 'recent') return (preferences.addedAt[b.id] || 0)-(preferences.addedAt[a.id] || 0) || a.label.localeCompare(b.label);
    return a.label.localeCompare(b.label);
  });
  function togglePack(id) {
    setPreferences(previous => {
      const installed = previous.installed.includes(id);
      return {...previous, installed: installed ? previous.installed.filter(item=>item!==id) : [...previous.installed,id], hidden: installed ? previous.hidden.filter(item=>item!==id) : previous.hidden, addedAt: installed ? previous.addedAt : {...previous.addedAt,[id]:Date.now()}};
    });
  }
  return <main className="pack-browser-page">
    <div className="pack-browser-bar"><input type="search" aria-label="Search packs" placeholder="Search packs" value={query} onChange={event=>setQuery(event.target.value)}/><label>Sort <select aria-label="Sort packs" value={sort} onChange={event=>setSort(event.target.value)}><option value="alphabetical">Alphabetical</option><option value="recent">Most recently added</option><option value="most">Most widgets</option></select></label></div>
    <div className="pack-browser-results">{sort==='recent' && <p className="pack-browser-note">Sorted by when you added each pack. Existing packs without an added date appear last.</p>}{packs.map(pack=><article className="pack-card" key={pack.id}><div><strong>{pack.label}</strong><p>{pack.description}</p><small>{pack.controls.length} widgets · {preferences.installed.includes(pack.id) ? (preferences.hidden.includes(pack.id) ? 'Added · hidden' : 'Added') : 'Not added'}</small></div><button type="button" aria-label={`${preferences.installed.includes(pack.id)?'Remove':'Add'} ${pack.label} pack`} onClick={()=>togglePack(pack.id)}>{preferences.installed.includes(pack.id)?'Remove':'Add'}</button></article>)}{!packs.length&&<p>No packs match “{query}”.</p>}</div>
  </main>;
}
