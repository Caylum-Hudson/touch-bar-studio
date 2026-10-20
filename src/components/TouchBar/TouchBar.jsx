import { useState, useRef, useEffect } from 'react';
import {
  SortableContext,
  horizontalListSortingStrategy,
} from '@dnd-kit/sortable';
import { useDroppable } from '@dnd-kit/core';
import { useApp } from '../../context/AppContext';
import TouchBarItem from './TouchBarItem';
import './TouchBar.css';
import {BAR_WIDTH,isPrecise,layoutFrames,overlappingItems,spacingGap,setConsistentSpacing} from '../../utils/positionLayout';
import ControlIcon from '../ControlIcon/ControlIcon';

export default function TouchBar() {
  const { items, selectItem, selectedItemId, removeItem, addItem, reorderItems } = useApp();
  const precise=isPrecise(items);
  const frames=layoutFrames(items);
  const [contextMenu, setContextMenu] = useState(null);
  const [spacingError, setSpacingError] = useState('');
  const [previewId, setPreviewId] = useState(null);
  const [previewValue, setPreviewValue] = useState(50);
  const gap = spacingGap(items);
  const expanded = items.find(item => item.id === previewId && ['volume','brightness'].includes(item.type));
  const chooseControl = item => {
    selectItem(item.id);
    if (['volume','brightness'].includes(item.type)) { setPreviewId(item.id); setPreviewValue(50); }
  };
  const applySpacing = (value, repack = false) => {
    try {
      const source = repack ? items.map(item => { const next={...item}; delete next.studioGap; return next; }) : items;
      reorderItems(setConsistentSpacing(source,value));
      setSpacingError('');
    } catch (error) { setSpacingError(error.message); }
  };
  const disableSpacing = () => reorderItems(items.map(item => { const next={...item}; delete next.studioGap; return next; }));
  const containerRef = useRef(null);

  // Make the touchbar a droppable area
  const { setNodeRef, isOver } = useDroppable({
    id: 'touchbar-drop-zone',
  });

  // Handle context menu
  const handleContextMenu = (e, itemId) => {
    e.preventDefault();
    e.stopPropagation();
    
    setContextMenu({
      x: e.clientX,
      y: e.clientY,
      itemId,
    });
  };

  // Close context menu on click outside
  useEffect(() => {
    const handleClickOutside = () => setContextMenu(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

  // Handle keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === 'Delete' || e.key === 'Backspace') {
        if (selectedItemId && document.activeElement.tagName !== 'INPUT' && document.activeElement.tagName !== 'TEXTAREA') {
          removeItem(selectedItemId);
        }
      }
      if (e.key === 'Escape') {
        selectItem(null);
        setContextMenu(null);
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [selectedItemId, removeItem, selectItem]);

  // Group items by alignment to match MTMR's actual layout
  const leftItems = items.filter(item => item.align === 'left');
  const centerItems = items.filter(item => !item.align || item.align === 'center');
  const rightItems = items.filter(item => item.align === 'right');

  return (
    <div className="touchbar-container" ref={containerRef}>
      <div className="layout-toolbar"><div><strong>Touch Bar layout</strong><span>{precise?'Editor preview · drag freely or set X in Properties':'Editor preview · automatic left, centre and right alignment'}</span></div><button aria-pressed={precise} onClick={()=>reorderItems(items.map(item=>{if(precise){const rest={...item};delete rest.studioPosition;delete rest.studioGap;return rest;}return {...item,studioPosition:frames.get(item.id).x,width:frames.get(item.id).width};}))}>{precise?'Use automatic alignment':'Precise placement'}</button></div>
      <div className="spacing-toolbar">
        <label><input type="checkbox" checked={gap !== null} disabled={!items.length} onChange={event => event.target.checked ? applySpacing(12) : disableSpacing()}/>Consistent spacing</label>
        {gap !== null && <><label>Gap <input aria-label="Consistent spacing gap" type="number" min="0" max="64" step="1" value={gap} onChange={event => applySpacing(event.target.value)}/> units</label><button onClick={()=>applySpacing(gap,true)}>Space all evenly</button></>}
        <span>{gap !== null ? 'Snap within 10 units of a neighbour; drag farther away to place freely.' : 'Enable to use equal gaps with optional free placement.'}</span>
      </div>
      {spacingError && <p className="layout-warning" role="alert">{spacingError}</p>}
      {expanded && <div className="expanded-slider-preview">
        <div className="expanded-slider-caption"><strong>{expanded.type === 'volume' ? 'Volume' : 'Brightness'} · expanded preview</strong><span>Preview only · adjust your Mac on the physical Touch Bar</span></div>
        <div className="expanded-slider-bar"><button onClick={()=>setPreviewId(null)} aria-label="Close expanded slider preview">‹ Back</button><div className="expanded-slider-center"><ControlIcon type={expanded.type === 'volume' ? 'mute' : 'brightnessDown'}/><input aria-label={`${expanded.type} slider preview`} type="range" min="0" max="100" value={previewValue} onChange={event=>setPreviewValue(+event.target.value)}/><ControlIcon type={expanded.type === 'volume' ? 'volumeUp' : 'brightnessUp'}/></div></div>
      </div>}
      {!expanded && <>
      {precise&&<><div className="position-help">1085-unit ruler · scales to the available Touch Bar width · width and X are editable in Properties</div><div className="precise-scroll"><div className="position-ruler" style={{width:BAR_WIDTH}}>{[0,100,200,300,400,500,600,700,800,900,1000,1085].map(x=><span key={x} style={{left:x===BAR_WIDTH?undefined:x,right:x===BAR_WIDTH?0:undefined}}>{x}</span>)}</div><div id="precise-touchbar-canvas" className="precise-canvas" style={{width:BAR_WIDTH}} ref={setNodeRef}><SortableContext items={items.map(i=>i.id)} strategy={horizontalListSortingStrategy}>{items.map(item=><div className="positioned-control" key={item.id} style={{left:frames.get(item.id).x,width:frames.get(item.id).width}}><TouchBarItem item={{...item,width:frames.get(item.id).width}} isSelected={selectedItemId===item.id} onSelect={()=>chooseControl(item)} onContextMenu={e=>handleContextMenu(e,item.id)}/></div>)}</SortableContext></div></div>{overlappingItems(items)&&<p className="layout-warning" role="status">Some controls overlap. Move them apart or reduce their widths so each control stays reachable.</p>}</>}
      {!precise&&<div className={`touchbar-frame ${isOver ? 'drag-over' : ''}`}>
        <div className="touchbar-screen" ref={setNodeRef}>
          <SortableContext items={items.map((i) => i.id)} strategy={horizontalListSortingStrategy}>
            <div className="touchbar-items">
              {items.length === 0 ? (
                <div className="touchbar-empty">
                  <span>Drag elements here or click from the palette</span>
                </div>
              ) : (
                <>
                  {/* Left-aligned items */}
                  <div className="touchbar-section touchbar-section-left">
                    {leftItems.map((item) => (
                      <TouchBarItem
                        key={item.id}
                        item={item}
                        isSelected={selectedItemId === item.id}
                        onSelect={() => chooseControl(item)}
                        onContextMenu={(e) => handleContextMenu(e, item.id)}
                      />
                    ))}
                  </div>

                  {/* Center-aligned items */}
                  <div className="touchbar-section touchbar-section-center">
                    {centerItems.map((item) => (
                      <TouchBarItem
                        key={item.id}
                        item={item}
                        isSelected={selectedItemId === item.id}
                        onSelect={() => chooseControl(item)}
                        onContextMenu={(e) => handleContextMenu(e, item.id)}
                      />
                    ))}
                  </div>

                  {/* Right-aligned items */}
                  <div className="touchbar-section touchbar-section-right">
                    {rightItems.map((item) => (
                      <TouchBarItem
                        key={item.id}
                        item={item}
                        isSelected={selectedItemId === item.id}
                        onSelect={() => chooseControl(item)}
                        onContextMenu={(e) => handleContextMenu(e, item.id)}
                      />
                    ))}
                  </div>
                </>
              )}
            </div>
          </SortableContext>
        </div>
      </div>

      }
      </>}
      {/* Context Menu */}
      {contextMenu && (
        <div
          className="context-menu"
          style={{
            position: 'fixed',
            left: contextMenu.x,
            top: contextMenu.y,
            zIndex: 1000,
          }}
          onClick={(e) => e.stopPropagation()}
        >
          <button
            className="context-menu-item"
            onClick={() => {
              selectItem(contextMenu.itemId);
              setContextMenu(null);
            }}
          >
            Edit
          </button>
          <button
            className="context-menu-item"
            onClick={() => {
              duplicateItem(contextMenu.itemId);
              setContextMenu(null);
            }}
          >
            Duplicate
          </button>
          <div className="context-menu-divider" />
          <button
            className="context-menu-item danger"
            onClick={() => {
              removeItem(contextMenu.itemId);
              setContextMenu(null);
            }}
          >
            Delete
          </button>
        </div>
      )}
    </div>
  );

  function duplicateItem(itemId) {
    const item = items.find((i) => i.id === itemId);
    if (item) {
      const itemWithoutId = {...item};
      delete itemWithoutId.id;
      addItem(item.type, itemWithoutId);
    }
  }
}