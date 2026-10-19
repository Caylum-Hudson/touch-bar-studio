import { useState, useRef, useEffect } from 'react';
import {
  SortableContext,
  horizontalListSortingStrategy,
} from '@dnd-kit/sortable';
import { useDroppable } from '@dnd-kit/core';
import { useApp } from '../../context/AppContext';
import TouchBarItem from './TouchBarItem';
import './TouchBar.css';
import {BAR_WIDTH,isPrecise,layoutFrames,overlappingItems} from '../../utils/positionLayout';

export default function TouchBar() {
  const { items, selectItem, selectedItemId, removeItem, addItem, reorderItems } = useApp();
  const precise=isPrecise(items);
  const frames=layoutFrames(items);
  const [contextMenu, setContextMenu] = useState(null);
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
      <div className="layout-toolbar"><div><strong>Touch Bar layout</strong><span>{precise?'Editor preview · drag freely or set X in Properties':'Editor preview · automatic left, centre and right alignment'}</span></div><button aria-pressed={precise} onClick={()=>reorderItems(items.map(item=>{if(precise){const {studioPosition:_position,...rest}=item;return rest;}return {...item,studioPosition:frames.get(item.id).x,width:frames.get(item.id).width};}))}>{precise?'Use automatic alignment':'Precise placement'}</button></div>
      {precise&&<><div className="position-help">1085-unit ruler · scales to the available Touch Bar width · width and X are editable in Properties</div><div className="precise-scroll"><div className="position-ruler" style={{width:BAR_WIDTH}}>{[0,100,200,300,400,500,600,700,800,900,1000,1085].map(x=><span key={x} style={{left:x===BAR_WIDTH?undefined:x,right:x===BAR_WIDTH?0:undefined}}>{x}</span>)}</div><div id="precise-touchbar-canvas" className="precise-canvas" style={{width:BAR_WIDTH}} ref={setNodeRef}><SortableContext items={items.map(i=>i.id)} strategy={horizontalListSortingStrategy}>{items.map(item=><div className="positioned-control" key={item.id} style={{left:frames.get(item.id).x,width:frames.get(item.id).width}}><TouchBarItem item={{...item,width:frames.get(item.id).width}} isSelected={selectedItemId===item.id} onSelect={()=>selectItem(item.id)} onContextMenu={e=>handleContextMenu(e,item.id)}/></div>)}</SortableContext></div></div>{overlappingItems(items)&&<p className="layout-warning" role="status">Some controls overlap. Move them apart or reduce their widths so each control stays reachable.</p>}</>}
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
                        onSelect={() => selectItem(item.id)}
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
                        onSelect={() => selectItem(item.id)}
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
                        onSelect={() => selectItem(item.id)}
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
      const { id, ...itemWithoutId } = item;
      addItem(item.type, itemWithoutId);
    }
  }
}