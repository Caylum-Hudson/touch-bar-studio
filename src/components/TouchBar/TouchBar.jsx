import { useState, useRef, useEffect, useCallback } from 'react';
import {
  SortableContext,
  horizontalListSortingStrategy,
} from '@dnd-kit/sortable';
import { useDroppable, useDndContext } from '@dnd-kit/core';
import { useApp } from '../../context/AppContext';
import { cloneWithoutRuntimeIdentity } from '../../utils/jsonGenerator';
import TouchBarItem from './TouchBarItem';
import './TouchBar.css';
import {BAR_WIDTH,isPrecise,layoutFrames,overlappingItems,spacingGap,setConsistentSpacing,autoDockDisplayWidth,contentFitWidth,distributeItemsEvenly,layoutContentScale,saveLayoutPositions} from '../../utils/positionLayout';
import ControlIcon from '../ControlIcon/ControlIcon';
import ControlStripPreview from './ControlStripPreview';
import { useRuntimePermissions } from '../../context/useRuntimePermissions';
import {previewProjection, projectFrame} from '../../utils/previewProjection.js';
import {matchSystemMonitorRuntimePreviews} from '../../utils/systemMonitorRuntimePreview.js';

// The native capacity API reports horizontal bounds only; Touch Bar controls use a 30 pt content row.
const NATIVE_PREVIEW_HEIGHT = 30;

export default function TouchBar({dockPreview = {apps: [], preferredWidth: null}}) {
  const { items, selectItem, selectedItemId, removeItem, addItem, reorderItems, profiles, profileId, resolvePageId, groupPath } = useApp();
  const { keepControlStrip, updateKeepControlStrip, native, layoutCapacity, systemMonitorPreviews, activeStudioGroupPath, activeRuntimeProfile, activeRuntimeResolvePage, activeRuntimeEnabled, previewScalePercent = 100, updatePreviewScalePercent } = useRuntimePermissions();
  const { active: draggedThing } = useDndContext();
  const draggingControlStrip = draggedThing?.data.current?.type === 'native-control-strip';
  const precise=isPrecise(items);
  const visibleRightEdge = BAR_WIDTH;
  const [containerWidth, setContainerWidth] = useState(BAR_WIDTH);
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
      const source = repack ? renderItems.map(item => { const next={...item}; delete next.studioGap; return next; }) : renderItems;
      const arranged = setConsistentSpacing(source,value);
      reorderItems(saveLayoutPositions(items,arranged,{clearGaps:repack}));
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
      const arranged = distributeItemsEvenly(renderItems, {dockPreferredWidth: dockPreview.preferredWidth, contentScale: contentScale || 1});
      const savedArranged = saveLayoutPositions(items,arranged,{clearGaps:true});
      placementFeedbackKey.current = JSON.stringify([placementContextKey, savedArranged]);
      reorderItems(savedArranged);
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
  }, [setNodeRef]);
  useEffect(() => {
    const node = containerRef.current;
    if (!node) return undefined;
    const measure = () => {
      const style = getComputedStyle(node);
      const horizontalPadding = parseFloat(style.paddingLeft || '0') + parseFloat(style.paddingRight || '0');
      const horizontalBorder = parseFloat(style.borderLeftWidth || '0') + parseFloat(style.borderRightWidth || '0');
      setContainerWidth(Math.max(1, node.clientWidth - horizontalPadding - horizontalBorder) || BAR_WIDTH);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  const matchedMonitorPreviews = matchSystemMonitorRuntimePreviews({rows:systemMonitorPreviews,profiles,profileId,resolvePageId,groupPath,activeProfile:activeRuntimeProfile,activeResolvePage:activeRuntimeResolvePage,activeGroupPath:activeStudioGroupPath,runtimeEnabled:activeRuntimeEnabled});
  const renderItems = items.map(item => item.type === 'systemMonitor' && item.autoFitContent && matchedMonitorPreviews.has(item.id)
    ? {...item,runtimePreview:matchedMonitorPreviews.get(item.id)} : item);
  const layoutOptions={dockPreferredWidth:dockPreview.preferredWidth,visibleRightEdge,contentScale:contentScale || 1};
  const frames=layoutFrames(renderItems,layoutOptions);
  const reservedWidth = groupPath.length ? 62 : profiles[profileId]?.bundleId === 'com.blackmagic-design.DaVinciResolve' ? 94 : 0;
  const physicalWidth = layoutCapacity?.physicalWidth > 0 ? layoutCapacity.physicalWidth : BAR_WIDTH;
  const projection = previewProjection(physicalWidth, {reserved:reservedWidth, availableWidth:containerWidth, extraWidth:(showControlStrip?176:0)+2, calibration:previewScalePercent/100});
  const projectedFrames = new Map([...frames].map(([id, frame]) => [id, projectFrame(frame, projection)]));
  const previewWidth = physicalWidth + (showControlStrip ? 176 : 0);
  const hasPreviewRuler = false;
  const previewContentHeight = hasPreviewRuler ? NATIVE_PREVIEW_HEIGHT + 31 : NATIVE_PREVIEW_HEIGHT;
  const previewOuterWidth = previewWidth + 2;
  const previewOuterHeight = previewContentHeight + 2;
  const previewScaleStyle = {width:previewWidth,transform:`scale(${projection.fitScale})`,transformOrigin:'top left',marginRight:(projection.fitScale-1)*previewOuterWidth,marginBottom:(projection.fitScale-1)*previewOuterHeight};
  const dockItem = renderItems.find(item=>item.type==='dock');
  const automaticOtherWidth = renderItems.filter(item=>item.type!=='dock').reduce((total,item)=>total+contentFitWidth(item),0);
  const automaticGaps = ['left','center','right'].reduce((total,alignment)=>{
    const count=renderItems.filter(item=>(item.align||'center')===alignment&&item.type!=='dock').length;
    return total+Math.max(0,count-1)*4;
  },0);
  const automaticAvailableWidth = Math.max(0,visibleRightEdge-12-automaticOtherWidth-automaticGaps);
  const automaticDockWidth = autoDockDisplayWidth(renderItems, dockItem?.id, dockPreview.preferredWidth, automaticAvailableWidth);
  const previewItem = item => {
    const logicalWidth=item.type==='dock'?(precise?frames.get(item.id).width:(automaticDockWidth ?? item.width)):(precise?frames.get(item.id).width:contentFitWidth(item));
    return {...item,width:projectedFrames.get(item.id)?.width ?? logicalWidth,...(item.type==='dock'?{dockApps:dockPreview.apps,dockIconSize:dockPreview.iconSize,dockItemSpacing:dockPreview.itemSpacing}:{})};
  };
  const projectedItems = renderItems.map(item => {
    const frame=projectedFrames.get(item.id);
    return <div className="positioned-control" key={item.id} style={{left:frame.x,width:frame.width}}><TouchBarItem item={previewItem(item)} dragScale={projection.fitScale} isSelected={selectedItemId===item.id} onSelect={()=>chooseControl(item)} onContextMenu={e=>handleContextMenu(e,item.id)}/></div>;
  });
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

  return (
    <div className="touchbar-container" ref={containerRef}>
      <div className="layout-heading"><strong>Touch Bar layout</strong><button type="button" onClick={async()=>{try {const response=await fetch("/api/control-strip-settings",{method:"POST"}).then(result=>result.json()); if(!response.success) setPlacementError(response.error || "Could not open Keyboard settings.");} catch {setPlacementError("Open System Settings → Keyboard → Touch Bar Settings to customise the Control Strip.");}}} title="Open macOS Keyboard settings to customise Apple’s Control Strip">Apple settings</button><button type="button" className="auto-place-button" disabled={!items.length} onClick={autoPlaceItems} title="Align the edge items with the usable bar edges and divide remaining space into equal interior gaps. Keeps item sizes and can be undone.">Auto-place evenly</button><details className="layout-settings"><summary>Layout settings <span>{precise?'Precise':'Automatic'}</span></summary><div className="layout-settings-content">
      <div className="layout-toolbar"><div><strong>Placement</strong><span>{precise?'Drag freely or set X in Properties':'Automatic left, centre and right alignment'}</span></div><button aria-pressed={precise} onClick={()=>reorderItems(items.map(item=>{if(precise){const rest={...item};delete rest.studioPosition;delete rest.studioGap;return rest;}return {...item,studioPosition:frames.get(item.id).x};}))}>{precise?'Use automatic alignment':'Precise placement'}</button></div>
      <div className="spacing-toolbar">
        <label><input type="checkbox" checked={gap !== null} disabled={!items.length} onChange={event => event.target.checked ? applySpacing(12) : disableSpacing()}/>Consistent spacing</label>
        {gap !== null && <><label>Gap <input aria-label="Consistent spacing gap" type="number" min="0" max="64" step="1" value={gap} onChange={event => applySpacing(event.target.value)}/> units</label><button onClick={()=>applySpacing(gap,true)}>Space all evenly</button></>}
        <span>{gap !== null ? 'Snap within 10 units of a neighbour; drag farther away to place freely.' : 'Enable to use equal gaps with optional free placement.'}</span>
      </div>
      <label className="preview-calibration-control">Preview width <span>{Math.min(100, previewScalePercent)}%</span><input aria-label="Preview width" type="range" min="50" max="100" step="5" value={Math.min(100, previewScalePercent)} onChange={event=>updatePreviewScalePercent?.(+event.target.value)}/><small>At 100%, the Touch Bar preview fills the available width. The bar and its controls keep their proportions.</small></label>

      {spacingError && <p className="layout-warning" role="alert">{spacingError}</p>}
      </div></details></div>
      {placementError && <p className="layout-warning auto-place-feedback" role="alert">{placementError}</p>}
      {placementStatus && <p className="auto-place-feedback" role="status">{placementStatus}</p>}
      {expanded && <div className="expanded-slider-preview">
        <div className="expanded-slider-caption"><strong>{expanded.type === 'volume' ? 'Volume' : 'Brightness'} · expanded preview</strong><span>Preview only · adjust your Mac on the physical Touch Bar</span></div>
        <div className="preview-scale-stage" style={{...previewScaleStyle,width:previewOuterWidth}}><div className="touchbar-frame preview-projected" style={{width:previewWidth}}><div className="touchbar-screen preview-projected expanded-slider-bar" style={{width:previewWidth,height:NATIVE_PREVIEW_HEIGHT}}><button onClick={()=>setPreviewId(null)} aria-label="Close expanded slider preview">‹ Back</button><div className="expanded-slider-center"><ControlIcon type={expanded.type === 'volume' ? 'mute' : 'brightnessDown'}/><input aria-label={`${expanded.type} slider preview`} type="range" min="0" max="100" value={previewValue} onChange={event=>setPreviewValue(+event.target.value)}/><ControlIcon type={expanded.type === 'volume' ? 'volumeUp' : 'brightnessUp'}/></div></div></div></div>
      </div>}
      {!expanded && <>
      {showControlStrip && controlStripExpanded ? (
        <div className="control-strip-expanded-stage">
          <div className="expanded-slider-caption control-strip-stage-header"><strong>macOS Control Strip · expanded</strong><span>Apple-style layout preview only · controls do not change your Mac</span><button type="button" onClick={()=>updateKeepControlStrip?.(false)} aria-label="Remove macOS Control Strip">Remove</button></div>
          <div className="preview-scale-stage" style={{...previewScaleStyle,width:previewOuterWidth}}><div className="touchbar-frame preview-projected" style={{width:previewWidth}}><div className="touchbar-screen preview-projected control-strip-full-screen" style={{width:previewWidth,height:NATIVE_PREVIEW_HEIGHT}}><ControlStripPreview expanded onCollapse={()=>setControlStripExpanded(false)}/></div></div></div>
        </div>
      ) : precise ? (
        <>
          <div className="preview-scale-stage precise-scale-stage" style={{...previewScaleStyle,width:previewOuterWidth}}>
            <div className={`touchbar-frame preview-projected ${showControlStrip?'with-control-strip':''} ${isOver?'drag-over':''}`} style={{width:previewWidth}}>
              <div className={`touchbar-screen preview-projected precise-preview ${showControlStrip?'with-control-strip':''}`} style={{width:previewWidth,height:NATIVE_PREVIEW_HEIGHT}}>
                <div className="precise-scroll" ref={attachViewport} style={{width:physicalWidth,flex:`0 0 ${physicalWidth}px`}}><div id="precise-touchbar-canvas" className="precise-canvas" data-base-scale={projection.baseScale} data-child-scale={projection.childScale} data-fit-scale={projection.fitScale} data-reserved={reservedWidth} style={{width:physicalWidth,height:NATIVE_PREVIEW_HEIGHT}}>{reservedWidth>0&&<div className="preview-native-navigation" style={{width:reservedWidth*projection.baseScale}} aria-label={groupPath.length?'Back to parent group':'Resolve page picker'}><span style={{width:(groupPath.length?54:94)*projection.baseScale}}>{groupPath.length?'‹ Back':'‹ Page'}</span></div>}<SortableContext items={items.map(i=>i.id)} strategy={horizontalListSortingStrategy}>{projectedItems}</SortableContext></div></div>
              {showControlStrip&&<div className="control-strip-widget-slot" ref={setControlStripSlotRef}><button type="button" className="control-strip-remove" onClick={()=>updateKeepControlStrip?.(false)} aria-label="Remove macOS Control Strip" title="Remove Control Strip">×</button><ControlStripPreview expanded={false} onExpand={()=>setControlStripExpanded(true)}/></div>}
              {controlStripDropTarget}
            </div>
            </div>
          </div>
          {overlappingItems(items,layoutOptions)&&<p className="layout-warning" role="status">Some controls overlap or need more room. Move them apart or adjust their widths so all content stays visible.</p>}
        </>
      ) : <div className={`touchbar-frame preview-projected ${showControlStrip?'with-control-strip':''} ${isOver ? 'drag-over' : ''}`} style={previewScaleStyle}>
        <div className={`touchbar-screen preview-projected ${showControlStrip?'with-control-strip':''}`} style={{width:previewWidth,height:previewContentHeight}}>
          <div className="touchbar-custom-region" ref={attachViewport} id="precise-touchbar-canvas" data-base-scale={projection.baseScale} data-child-scale={projection.childScale} data-fit-scale={projection.fitScale} data-reserved={reservedWidth} style={{width:physicalWidth,flex:`0 0 ${physicalWidth}px`,height:NATIVE_PREVIEW_HEIGHT,position:'relative',overflow:'hidden'}}>
          {reservedWidth>0&&<div className="preview-native-navigation" style={{width:reservedWidth*projection.baseScale}} aria-label={groupPath.length?'Back to parent group':'Resolve page picker'}><span style={{width:(groupPath.length?54:94)*projection.baseScale}}>{groupPath.length?'‹ Back':'‹ Page'}</span></div>}
          <SortableContext items={items.map((i) => i.id)} strategy={horizontalListSortingStrategy}>{projectedItems}</SortableContext>
          {items.length===0&&<div className="touchbar-empty" style={{width:physicalWidth}}>Drag elements here or click from the palette</div>}
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
      addItem(item.type, cloneWithoutRuntimeIdentity(item));
    }
  }
}
