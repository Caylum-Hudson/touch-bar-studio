import { useEffect, useMemo, useState } from 'react';
import { useDraggable } from '@dnd-kit/core';
import { useApp } from '../../context/AppContext';
import { useRuntimePermissions } from '../../context/useRuntimePermissions';
import { advancedControlCatalog } from '../../data/controlCatalog';
import { controlPacks, defaultControlPackPreferences, hiddenControlPacks, normalizeControlPackPreferences } from '../../data/controlPacks';
import { getControlStatus } from '../../data/controlAvailability';
import ControlIcon from '../ControlIcon/ControlIcon';
import './Palette.css';

export default function Palette() {
  const { addItem, selectItem } = useApp();
  const { accessibilityAccess, keepControlStrip, updateKeepControlStrip, controlStripBusy } = useRuntimePermissions();
  const [searchQuery, setSearchQuery] = useState('');
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const [expandedCategories, setExpandedCategories] = useState({});
  const [packPreferences, setPackPreferences] = useState(() => {
    try { return normalizeControlPackPreferences(JSON.parse(localStorage.getItem('mtmr-control-packs'))); }
    catch { return defaultControlPackPreferences; }
  });

  useEffect(() => { localStorage.setItem('mtmr-control-packs', JSON.stringify(packPreferences)); }, [packPreferences]);


  const query = searchQuery.trim().toLowerCase();
  const filterGroups = useMemo(() => (groups) => groups.map((group) => ({
    ...group,
    controls: group.controls.map((control) => ({
      ...control,
      runtimeStatus: getControlStatus(control, accessibilityAccess),
    })).filter((control) => !query || [control.label, control.key, control.benefit, control.runtimeStatus]
      .some((value) => value.toLowerCase().includes(query))),
  })).filter((group) => group.controls.length > 0), [query, accessibilityAccess]);
  const visible = new Set(packPreferences.installed.filter((id) => !packPreferences.hidden.includes(id)));
  const favoriteKeys = new Set(packPreferences.favorites);
  const filteredGroups = filterGroups(controlPacks);
  const advancedIds = new Set(advancedControlCatalog.map(({ id }) => id));
  const commonGroups = filteredGroups.filter((group) => visible.has(group.id) && !advancedIds.has(group.id));
  const visibleAdvancedGroups = filteredGroups.filter((group) => visible.has(group.id) && advancedIds.has(group.id));
  const hiddenGroups = filterGroups(hiddenControlPacks(packPreferences));
  const favoriteControls = controlPacks.flatMap((group) => group.controls).filter((control) => favoriteKeys.has(control.key));

  const toggleCategory = (id) => setExpandedCategories((previous) => ({ ...previous, [id]: previous[id] === false }));
  const addControl = (key) => {
    const item = addItem(key);
    if (item) selectItem(item.id);
  };
  const updatePack = (id, update) => setPackPreferences((previous) => ({ ...previous, ...update(previous) }));
  const toggleFavorite = (key) => updatePack(key, (previous) => ({ favorites: previous.favorites.includes(key) ? previous.favorites.filter((item) => item !== key) : [...previous.favorites, key] }));

  return (
    <div className="palette">
      <div className="palette-header">
        <div className="palette-heading">
          <div><h2>Add controls</h2><p>Drag a widget down to the Touch Bar or use + to add it.</p></div>
          <span className="palette-count">{commonGroups.reduce((total, group) => total + group.controls.length, 0)}</span>
        </div>
        <label className="palette-search">
          <span className="palette-search-icon" aria-hidden="true">⌕</span>
          <input
            type="search"
            className="palette-search-input"
            placeholder="Find a control"
            value={searchQuery}
            onChange={(event) => setSearchQuery(event.target.value)}
            aria-label="Find a control"
          />
          {searchQuery && <button type="button" className="palette-search-clear" onClick={() => setSearchQuery('')} aria-label="Clear search">×</button>}
        </label>
      </div>
      <div className="palette-content">
        <div className="palette-items">
          <ControlStripPaletteCard added={keepControlStrip} busy={controlStripBusy} onToggle={updateKeepControlStrip}/>
        </div>
        <details className="palette-quick-access"><summary>Favorites <span>{favoriteControls.length}</span></summary>
          {favoriteControls.length ? <div className="palette-items">{favoriteControls.map((control) => <PaletteItem key={control.key} control={control} onAdd={() => addControl(control.key)} favorite onFavorite={() => toggleFavorite(control.key)} />)}</div> : <p>Star controls to keep them here.</p>}
        </details>
        <p className="palette-section-title">COMMON CONTROLS</p>
        {commonGroups.map((group) => (
          <PaletteCategory key={group.id} group={group} expanded={query || expandedCategories[group.id] !== false} onToggle={() => toggleCategory(group.id)} onAdd={addControl} favoriteKeys={favoriteKeys} onFavorite={toggleFavorite} onHide={() => updatePack(group.id, (previous) => ({ hidden: [...new Set([...previous.hidden, group.id])] }))} />
        ))}
        {hiddenGroups.length > 0 && <details className="palette-quick-access"><summary>More controls <span>{hiddenGroups.length} hidden packs</span></summary><p>Hidden packs stay installed and available here.</p>{hiddenGroups.map((group) => <PaletteCategory key={group.id} group={group} expanded={query || expandedCategories[group.id] !== false} onToggle={() => toggleCategory(group.id)} onAdd={addControl} favoriteKeys={favoriteKeys} onFavorite={toggleFavorite} onShow={() => updatePack(group.id, (previous) => ({ hidden: previous.hidden.filter((id) => id !== group.id) }))} />)}</details>}
        {visibleAdvancedGroups.length > 0 && (
          <section className="palette-advanced">
            <button className="palette-advanced-toggle" type="button" aria-expanded={advancedOpen || Boolean(query)} onClick={() => setAdvancedOpen((open) => !open)}>
              <span><strong>Advanced & legacy</strong><small>Service setup, special actions and older controls</small></span>
              <span className="advanced-chevron">{advancedOpen || query ? '−' : '+'}</span>
            </button>
            {(advancedOpen || query) && visibleAdvancedGroups.map((group) => (
              <PaletteCategory key={group.id} group={group} expanded={query || expandedCategories[group.id] !== false} onToggle={() => toggleCategory(group.id)} onAdd={addControl} favoriteKeys={favoriteKeys} onFavorite={toggleFavorite} onHide={() => updatePack(group.id, (previous) => ({ hidden: [...new Set([...previous.hidden, group.id])] }))} />
            ))}
          </section>
        )}
        {!commonGroups.length && !hiddenGroups.length && <div className="palette-no-results">No controls match “{searchQuery}”.</div>}

      </div>
    </div>
  );
}

function ControlStripPaletteCard({ added, busy, onToggle }) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: 'palette-native-control-strip',
    disabled: added || busy || !onToggle,
    data: { type: 'native-control-strip' },
  });
  return (
    <article className={`palette-item native-control-strip-card ${isDragging ? 'is-dragging' : ''}`}>
      <ControlIcon type="brightness" className="palette-item-icon" />
      <span className="palette-item-copy">
        <span className="palette-item-label">macOS Control Strip</span>
        <span className="palette-item-benefit">Adds macOS controls at the Touch Bar’s right edge.</span>
        <span className="palette-item-status">{added ? 'Added' : 'Right edge only'}</span>
      </span>
      <button type="button" className="palette-add" disabled={added || busy || !onToggle} onClick={() => onToggle?.(true)} aria-label={added ? 'macOS Control Strip added' : 'Add macOS Control Strip'}>{added ? '✓' : '+'}</button>
      <button ref={setNodeRef} type="button" className="palette-drag" disabled={added || busy || !onToggle} aria-label="Drag macOS Control Strip to the right edge" title="Drag to the right edge" {...attributes} {...listeners}>⠿</button>
    </article>
  );
}

function PaletteCategory({ group, expanded, onToggle, onAdd, favoriteKeys = new Set(), onFavorite, onHide, onShow }) {
  return (
    <section className="palette-category">
      <div className="palette-category-header">
        <button type="button" className="pack-category-toggle" onClick={onToggle} aria-expanded={Boolean(expanded)}>
        <span className={`category-chevron ${expanded ? 'is-expanded' : ''}`} aria-hidden="true">›</span>
        <span className="category-heading"><strong>{group.label}</strong><small>{group.description}</small></span>
        <span className="category-count">{group.controls.length}</span>
        </button>
        {(onHide || onShow) && <span className="pack-actions"><button type="button" title={onHide ? `Hide ${group.label} pack` : `Show ${group.label} pack`} onClick={onHide || onShow} aria-label={onHide ? `Hide ${group.label} pack` : `Show ${group.label} pack`}><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>{onShow && <path d="M4 4l16 16"/>}</svg></button></span>}
      </div>
      {expanded && <div className="palette-items">
        {group.controls.map((control) => <PaletteItem key={control.key} control={control} onAdd={() => onAdd(control.key)} favorite={favoriteKeys.has(control.key)} onFavorite={() => onFavorite?.(control.key)} />)}
      </div>}
    </section>
  );
}

function PaletteItem({ control, onAdd, favorite, onFavorite }) {
  const key = control.key || control.type;
  const unavailable = control.status.startsWith('Unavailable');
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: `palette-${key}`,
    disabled: unavailable,
    data: { type: 'palette-item', elementType: key, nativeType: control.type, elementKey: key, defaultProps: control.defaultProps },
  });

  return (
    <article className={`palette-item ${isDragging ? 'is-dragging' : ''}`}>
      <button ref={setNodeRef} type="button" className="palette-icon-drag" disabled={unavailable} aria-label={`Drag ${control.label} to the Touch Bar`} title="Drag down to the Touch Bar" {...attributes} {...listeners}><ControlIcon type={key} className="palette-item-icon" /></button>
      <span className="palette-item-copy">
        <span className="palette-item-label">{control.label}</span>
        <span className="palette-item-benefit">{control.benefit}</span>
      <span className="palette-item-status">{control.runtimeStatus || control.status}</span>
      </span>
      {onFavorite && <button type="button" className={`palette-favorite ${favorite ? 'is-favorite' : ''}`} aria-label={`${favorite ? 'Remove' : 'Add'} ${control.label} ${favorite ? 'from' : 'to'} favorites`} onClick={onFavorite}>{favorite ? '★' : '☆'}</button>}
      <button type="button" className="palette-add" disabled={unavailable} onClick={onAdd} aria-label={`Add ${control.label}`} title={`Add ${control.label}`}>+</button>

    </article>
  );
}
