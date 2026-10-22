import { useState, useRef, useEffect, useCallback } from 'react';
import {
  SortableContext,
  horizontalListSortingStrategy,
} from '@dnd-kit/sortable';
import { useDroppable, useDndContext } from '@dnd-kit/core';
import { useApp } from '../../context/AppContext';
import TouchBarItem from './TouchBarItem';
import './TouchBar.css';
import {BAR_WIDTH,isPrecise,layoutFrames,overlappingItems,spacingGap,setConsistentSpacing,autoDockDisplayWidth,contentFitWidth,distributeItemsEvenly,layoutContentScale} from '../../utils/positionLayout';
import ControlIcon from '../ControlIcon/ControlIcon';
import ControlStripPreview from './ControlStripPreview';
import { useRuntimePermissions } from '../../context/useRuntimePermissions';

export default function TouchBar({dockPreview = {apps: [], preferredWidth: null}}) {
  const { items, selectItem, selectedItemId, removeItem, addItem, reorderItems, profiles, profileId, groupPath } = useApp();
  const { keepControlStrip, updateKeepControlStrip, native, layoutCapacity } = useRuntimePermissions();
  const { active: draggedThing } = useDndContext();
  const draggingControlStrip = draggedThing?.data.current?.type === 'native-control-strip';
  const precise=isPrecise(items);
  const [viewportNode, setViewportNode] = useState(null);
  const [visibleRightEdge, setVisibleRightEdge] = useState(BAR_WIDTH);
  const [contextMenu, setContextMenu] = useState(null);
  const [spacingError, setSpacingError] = useState('');
  const [placementError, setPlacementError] = useState('');
  const [placementStatus, setPlacementStatus] = useState('');
  const placementFeedbackKey = useRef(null);
  const placementContextKey = JSON.stringify([profileId, groupPath]);
  const currentPlacementKey = JSON.stringify([placementContextKey, items]);
  useEffect(() => {
    if (placementFeedbackKey.current !== currentPlacementKey) {
      setPlacementError('');
      setPlacementStatus('');
      placementFeedbackKey.current = null;
    }
  }, [currentPlacementKey]);
  const [previewId, setPreviewId] = useState(null);
  const [previewValue, setPreviewValue] = useState(50);
  const [controlStripExpanded, setControlStripExpanded] = useState(false);
  const gap = spacingGap(items);
  const expanded = items.find(item => item.id === previewId && ['volume','brightness'].includes(item.type));
  const showControlStrip = keepControlStrip && !expanded;
  useEffect(() => {
    if (!keepControlStrip) setControlStripExpanded(false);
  }, [keepControlStrip]);
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
  const contentScale = layoutContentScale(layoutCapacity, {
    submenu: groupPath.length > 0,
    resolveProfile: profiles[profileId]?.bundleId === 'com.blackmagic-design.DaVinciResolve',
  });
  const placementUnavailable = native && (!contentScale || layoutCapacity.keepControlStrip !== keepControlStrip);
  const autoPlaceItems = () => {
    try {
      if (placementUnavailable) throw new Error('Turn on the Touch Bar and wait for its size to be available, then try again.');
      if (native && items.some(item => item.type === 'dock' && item.autoResize !== false) && !Number.isFinite(dockPreview.preferredWidth)) throw new Error('Wait for the Dock preview to load, then try again.');
      const arranged = distributeItemsEvenly(items, {dockPreferredWidth: dockPreview.preferredWidth, contentScale: contentScale || 1});
      placementFeedbackKey.current = JSON.stringify([placementContextKey, arranged]);
      reorderItems(arranged);
      setPlacementError('');
      setPlacementStatus('Items placed evenly.');
    } catch (error) {
      placementFeedbackKey.current = currentPlacementKey;
      setPlacementError(error.message);
      setPlacementStatus('');
    }
  };
  const disableSpacing = () => reorderItems(items.map(item => { const next={...item}; delete next.studioGap; return next; }));
  const containerRef = useRef(null);

  // Make the touchbar a droppable area
  const { setNodeRef, isOver } = useDroppable({
    id: 'touchbar-drop-zone',
  });
  const attachViewport = useCallback(node => {
    setNodeRef(node);
    setViewportNode(node);
  }, [setNodeRef]);
  useEffect(() => {
    if (!viewportNode) { setVisibleRightEdge(BAR_WIDTH); return undefined; }
    const measure = () => setVisibleRightEdge(viewportNode.scrollLeft + viewportNode.clientWidth);
    measure();
    viewportNode.addEventListener('scroll', measure, {passive: true});
    const observer = new ResizeObserver(measure);
    observer.observe(viewportNode);
    return () => { viewportNode.removeEventListener('scroll', measure); observer.disconnect(); };
  }, [viewportNode]);
  const layoutOptions={dockPreferredWidth:dockPreview.preferredWidth,visibleRightEdge,contentScale:contentScale || 1};
  const frames=layoutFrames(items,layoutOptions);
  const dockItem = items.find(item=>item.type==='dock');
  const automaticOtherWidth = items.filter(item=>item.type!=='dock').reduce((total,item)=>total+contentFitWidth(item),0);
  const automaticGaps = ['left','center','right'].reduce((total,alignment)=>{
    const count=items.filter(item=>(item.align||'center')===alignment&&item.type!=='dock').length;
    return total+Math.max(0,count-1)*4;
  },0);
  const automaticAvailableWidth = Math.max(0,visibleRightEdge-12-automaticOtherWidth-automaticGaps);
  const automaticDockWidth = autoDockDisplayWidth(items, dockItem?.id, dockPreview.preferredWidth, automaticAvailableWidth);
  const previewItem = item => item.type==='dock'
    ? {...item,width:precise?frames.get(item.id).width:(automaticDockWidth ?? item.width),dockApps:dockPreview.apps,dockIconSize:dockPreview.iconSize,dockItemSpacing:dockPreview.itemSpacing}
    : {...item,width:precise?frames.get(item.id).width:contentFitWidth(item)};
  const { setNodeRef: setControlStripSlotRef, isOver: isOverControlStripSlot } = useDroppable({
    id: 'control-strip-slot',
    disabled: keepControlStrip,
  });
  const controlStripDropTarget = !keepControlStrip && (
    <div className={`control-strip-drop-target ${draggingControlStrip ? 'is-active' : ''} ${isOverControlStripSlot ? 'is-over' : ''}`} ref={setControlStripSlotRef} aria-label="Drop to add macOS Control Strip at the right edge">
      <span>{isOverControlStripSlot ? 'Release to add Control Strip' : 'Drop Control Strip here'}</span>
    </div>
  );

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
      <div className="layout-heading"><strong>Touch Bar layout</strong><button type="button" className="auto-place-button" disabled={!items.length} onClick={autoPlaceItems} title="Distribute current items with equal space around them. Keeps their sizes and can be undone.">Auto-place evenly</button><details className="layout-settings"><summary>Layout settings <span>{precise?'Precise':'Automatic'}</span></summary><div className="layout-settings-content">
      <div className="layout-toolbar"><div><strong>Placement</strong><span>{precise?'Drag freely or set X in Properties':'Automatic left, centre and right alignment'}</span></div><button aria-pressed={precise} onClick={()=>reorderItems(items.map(item=>{if(precise){const rest={...item};delete rest.studioPosition;delete rest.studioGap;return rest;}return {...item,studioPosition:frames.get(item.id).x};}))}>{precise?'Use automatic alignment':'Precise placement'}</button></div>
      <div className="spacing-toolbar">
        <label><input type="checkbox" checked={gap !== null} disabled={!items.length} onChange={event => event.target.checked ? applySpacing(12) : disableSpacing()}/>Consistent spacing</label>
        {gap !== null && <><label>Gap <input aria-label="Consistent spacing gap" type="number" min="0" max="64" step="1" value={gap} onChange={event => applySpacing(event.target.value)}/> units</label><button onClick={()=>applySpacing(gap,true)}>Space all evenly</button></>}
        <span>{gap !== null ? 'Snap within 10 units of a neighbour; drag farther away to place freely.' : 'Enable to use equal gaps with optional free placement.'}</span>
      </div>
      {precise && <p className="position-help">The ruler uses the full 1085-unit Touch Bar coordinate system.</p>}
      {spacingError && <p className="layout-warning" role="alert">{spacingError}</p>}
      </div></details></div>
      {placementError && <p className="layout-warning auto-place-feedback" role="alert">{placementError}</p>}
      {placementStatus && <p className="auto-place-feedback" role="status">{placementStatus}</p>}
      {expanded && <div className="expanded-slider-preview">
        <div className="expanded-slider-caption"><strong>{expanded.type === 'volume' ? 'Volume' : 'Brightness'} · expanded preview</strong><span>Preview only · adjust your Mac on the physical Touch Bar</span></div>
        <div className="expanded-slider-bar"><button onClick={()=>setPreviewId(null)} aria-label="Close expanded slider preview">‹ Back</button><div className="expanded-slider-center"><ControlIcon type={expanded.type === 'volume' ? 'mute' : 'brightnessDown'}/><input aria-label={`${expanded.type} slider preview`} type="range" min="0" max="100" value={previewValue} onChange={event=>setPreviewValue(+event.target.value)}/><ControlIcon type={expanded.type === 'volume' ? 'volumeUp' : 'brightnessUp'}/></div></div>
      </div>}
      {!expanded && <>
      {showControlStrip && controlStripExpanded ? (
        <div className="control-strip-expanded-stage">
          <div className="expanded-slider-caption control-strip-stage-header"><strong>macOS Control Strip · expanded</strong><span>Apple-style layout preview only · controls do not change your Mac</span><button type="button" onClick={()=>updateKeepControlStrip?.(false)} aria-label="Remove macOS Control Strip">Remove</button></div>
          <div className="touchbar-frame control-strip-full-frame"><div className="touchbar-screen control-strip-full-screen"><ControlStripPreview expanded onCollapse={()=>setControlStripExpanded(false)}/></div></div>
        </div>
      ) : precise ? (
        <>
          <div className={`touchbar-frame ${showControlStrip?'with-control-strip':''} ${isOver?'drag-over':''}`}>
            <div className={`touchbar-screen ${showControlStrip?'with-control-strip':''}`}>
              <div className="precise-scroll" ref={attachViewport}><div className="position-ruler" style={{width:BAR_WIDTH}}>{[0,100,200,300,400,500,600,700,800,900,1000,1085].map(x=><span key={x} style={{left:x===BAR_WIDTH?undefined:x,right:x===BAR_WIDTH?0:undefined}}>{x}</span>)}</div><div id="precise-touchbar-canvas" className="precise-canvas" style={{width:BAR_WIDTH}}><SortableContext items={items.map(i=>i.id)} strategy={horizontalListSortingStrategy}>{items.map(item=><div className="positioned-control" key={item.id} style={{left:frames.get(item.id).x,width:frames.get(item.id).width}}><TouchBarItem item={previewItem({...item,width:frames.get(item.id).width})} isSelected={selectedItemId===item.id} onSelect={()=>chooseControl(item)} onContextMenu={e=>handleContextMenu(e,item.id)}/></div>)}</SortableContext></div></div>
              {showControlStrip&&<div className="control-strip-widget-slot" ref={setControlStripSlotRef}><button type="button" className="control-strip-remove" onClick={()=>updateKeepControlStrip?.(false)} aria-label="Remove macOS Control Strip" title="Remove Control Strip">×</button><ControlStripPreview expanded={false} onExpand={()=>setControlStripExpanded(true)}/></div>}
              {controlStripDropTarget}
            </div>
          </div>
          {overlappingItems(items,layoutOptions)&&<p className="layout-warning" role="status">Some controls overlap or need more room. Move them apart or adjust their widths so all content stays visible.</p>}
        </>
      ) : <div className={`touchbar-frame ${showControlStrip?'with-control-strip':''} ${isOver ? 'drag-over' : ''}`}>
        <div className={`touchbar-screen ${showControlStrip?'with-control-strip':''}`}>
          <div className="touchbar-custom-region" ref={attachViewport}>
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
                        item={previewItem(item)}
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
                        item={previewItem(item)}
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
                        item={previewItem(item)}
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
          {showControlStrip&&<div className="control-strip-widget-slot" ref={setControlStripSlotRef}><button type="button" className="control-strip-remove" onClick={()=>updateKeepControlStrip?.(false)} aria-label="Remove macOS Control Strip" title="Remove Control Strip">×</button><ControlStripPreview expanded={false} onExpand={()=>setControlStripExpanded(true)}/></div>}
          {controlStripDropTarget}
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
