import { useMemo, useState } from 'react';
import { useDraggable } from '@dnd-kit/core';
import { useApp } from '../../context/AppContext';
import { useRuntimePermissions } from '../../context/useRuntimePermissions';
import { controlCatalog, advancedControlCatalog } from '../../data/controlCatalog';
import { getControlStatus } from '../../data/controlAvailability';
import ControlIcon from '../ControlIcon/ControlIcon';
import './Palette.css';

export default function Palette() {
  const { addItem, selectItem } = useApp();
  const { accessibilityAccess, keepControlStrip, updateKeepControlStrip, controlStripBusy } = useRuntimePermissions();
  const [searchQuery, setSearchQuery] = useState('');
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const [expandedCategories, setExpandedCategories] = useState({});

  const query = searchQuery.trim().toLowerCase();
  const filterGroups = useMemo(() => (groups) => groups.map((group) => ({
    ...group,
    controls: group.controls.map((control) => ({
      ...control,
      runtimeStatus: getControlStatus(control, accessibilityAccess),
    })).filter((control) => !query || [control.label, control.key, control.benefit, control.runtimeStatus]
      .some((value) => value.toLowerCase().includes(query))),
  })).filter((group) => group.controls.length > 0), [query, accessibilityAccess]);
  const commonGroups = filterGroups(controlCatalog);
  const advancedGroups = filterGroups(advancedControlCatalog);

  const toggleCategory = (id) => setExpandedCategories((previous) => ({ ...previous, [id]: previous[id] === false }));
  const addControl = (key) => {
    const item = addItem(key);
    if (item) selectItem(item.id);
  };

  return (
    <div className="palette">
      <div className="palette-header">
        <div className="palette-heading">
          <div><h2>Add controls</h2><p>Choose a control, then customize it.</p></div>
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
        <p className="palette-section-title">COMMON CONTROLS</p>
        {commonGroups.map((group) => (
          <PaletteCategory key={group.id} group={group} expanded={query || expandedCategories[group.id] !== false} onToggle={() => toggleCategory(group.id)} onAdd={addControl} />
        ))}
        {advancedGroups.length > 0 && (
          <section className="palette-advanced">
            <button className="palette-advanced-toggle" type="button" aria-expanded={advancedOpen || Boolean(query)} onClick={() => setAdvancedOpen((open) => !open)}>
              <span><strong>Advanced & legacy</strong><small>Service setup, special actions and older controls</small></span>
              <span className="advanced-chevron">{advancedOpen || query ? '−' : '+'}</span>
            </button>
            {(advancedOpen || query) && advancedGroups.map((group) => (
              <PaletteCategory key={group.id} group={group} expanded={query || expandedCategories[group.id] !== false} onToggle={() => toggleCategory(group.id)} onAdd={addControl} />
            ))}
          </section>
        )}
        {!commonGroups.length && !advancedGroups.length && <div className="palette-no-results">No controls match “{searchQuery}”.</div>}
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

function PaletteCategory({ group, expanded, onToggle, onAdd }) {
  return (
    <section className="palette-category">
      <button type="button" className="palette-category-header" onClick={onToggle} aria-expanded={Boolean(expanded)}>
        <span className={`category-chevron ${expanded ? 'is-expanded' : ''}`} aria-hidden="true">›</span>
        <span className="category-heading"><strong>{group.label}</strong><small>{group.description}</small></span>
        <span className="category-count">{group.controls.length}</span>
      </button>
      {expanded && <div className="palette-items">
        {group.controls.map((control) => <PaletteItem key={control.key} control={control} onAdd={() => onAdd(control.key)} />)}
      </div>}
    </section>
  );
}

function PaletteItem({ control, onAdd }) {
  const key = control.key || control.type;
  const unavailable = control.status.startsWith('Unavailable');
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: `palette-${key}`,
    disabled: unavailable,
    data: { type: 'palette-item', elementType: key, nativeType: control.type, elementKey: key, defaultProps: control.defaultProps },
  });

  return (
    <article className={`palette-item ${isDragging ? 'is-dragging' : ''}`}>
      <ControlIcon type={key} className="palette-item-icon" />
      <span className="palette-item-copy">
        <span className="palette-item-label">{control.label}</span>
        <span className="palette-item-benefit">{control.benefit}</span>
      <span className="palette-item-status">{control.runtimeStatus || control.status}</span>
      </span>
      <button type="button" className="palette-add" disabled={unavailable} onClick={onAdd} aria-label={`Add ${control.label}`} title={`Add ${control.label}`}>+</button>
      <button
        ref={setNodeRef}
        type="button"
        className="palette-drag"
        disabled={unavailable}
        aria-label={`Drag ${control.label} to the Touch Bar`}
        title="Drag to the Touch Bar"
        {...attributes}
        {...listeners}
      >⠿</button>
    </article>
  );
}
