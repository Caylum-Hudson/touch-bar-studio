import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { getElementDefinition } from '../../data/elementDefinitions';
import ControlIcon from '../ControlIcon/ControlIcon';
import {fitDockIcons} from '../../utils/positionLayout';
import {formatTimePreview} from '../../utils/widgetSizing';
import {selectedSystemMonitorMetrics, systemMonitorPreview} from '../../utils/systemMonitor';
import './TouchBar.css';

// Get display content for an item based on its type
function getItemDisplay(item, definition) {
  const type = item.type;

  if (type === 'resolveNumericDial') return { type: 'resolve-numeric-dial' };

  // Handle items with custom images
  if (item.image?.base64) {
    return { type: 'image', content: `data:image/png;base64,${item.image.base64}` };
  }

  // Handle items with custom titles
  if (item.title && item.title.trim()) {
    return { type: 'text', content: item.title };
  }

  // Type-specific displays
  switch (type) {
    case 'resolveColorDial':
      return { type: 'resolve-color-dial' };
    case 'resolveTimelineJog':
      return { type: 'resolve-timeline-jog' };
    case 'escape':
      return { type: 'text', content: 'esc' };
    case 'exitTouchbar':
      return { type: 'icon', controlType: type };
    case 'brightnessUp':
      return { type: 'icon', controlType: type };
    case 'brightnessDown':
      return { type: 'icon', controlType: type };
    case 'brightness':
      return { type: 'icon', controlType: type };
    case 'illuminationUp':
      return { type: 'icon', controlType: type };
    case 'illuminationDown':
      return { type: 'icon', controlType: type };
    case 'volumeUp':
      return { type: 'icon', controlType: type };
    case 'volumeDown':
      return { type: 'icon', controlType: type };
    case 'volume':
      return { type: 'icon', controlType: type };
    case 'mute':
      return { type: 'icon', controlType: type };
    case 'delete':
      return { type: 'text', content: 'del' };
    case 'sleep':
      return { type: 'icon', controlType: type };
    case 'displaySleep':
      return { type: 'icon', controlType: type };
    case 'previous':
      return { type: 'icon', controlType: type };
    case 'play':
      return { type: 'icon', controlType: type };
    case 'next':
      return { type: 'icon', controlType: type };
    case 'battery':
      return { type: 'sample', controlType: type, content: 'Battery' };
    case 'timeButton':
      return { type: 'text', content: formatTimePreview(item.formatTemplate || 'HH:mm', item.timeZone) };
    case 'weather':
    case 'yandexWeather':
      return { type: 'sample', controlType: type, content: 'Weather' };
    case 'cpu':
      return { type: 'sample', controlType: type, content: '100%' };
    case 'ramUsage':
      return { type: 'sample', controlType: type, content: '100%' };
    case 'gpuUsage':
      return { type: 'sample', controlType: type, content: '100%' };
    case 'boardTemperature':
      return { type: 'sample', controlType: type, content: 'Board —' };
    case 'cpuTemperature':
      return { type: 'sample', controlType: type, content: '130°C' };
    case 'systemMonitor':
      return { type: 'sample', controlType: type, content: systemMonitorPreview(item).join(' · ') };
    case 'currency':
      return { type: 'text', content: `${item.from || 'BTC'}→${item.to || 'USD'}` };
    case 'music':
      return { type: 'sample', controlType: type, content: 'Music' };
    case 'dock':
      return { type: 'dock' };
    case 'nightShift':
      return { type: 'icon', controlType: type };
    case 'dnd':
      return { type: 'icon', controlType: type };
    case 'darkMode':
      return { type: 'icon', controlType: type };
    case 'pomodoro':
      return { type: 'sample', controlType: type, content: 'Focus' };
    case 'network':
      return { type: 'sample', controlType: type, content: 'Network' };
    case 'inputsource':
      return { type: 'sample', controlType: type, content: 'Input source' };
    case 'upnext':
      return { type: 'sample', controlType: type, content: 'Up next' };
    case 'close':
      return { type: 'icon', controlType: type };
    case 'group':
      return { type: 'group', content: item.title || 'Group', count: item.items?.length || 0 };
    case 'swipe':
      return { type: 'icon', controlType: type };
    case 'staticButton':
    case 'appleScriptTitledButton':
    case 'shellScriptTitledButton':
      return { type: 'text', content: item.title || definition?.defaultTitle || 'Button' };
    default:
      return { type: 'text', content: definition?.defaultTitle || type };
  }
}

export default function TouchBarItem({ item, isSelected, onSelect, onContextMenu, dragScale = 1 }) {
  const definition = getElementDefinition(item.type);
  
  // Debug: Log when definition is not found
  if (!definition) {
    console.log('TouchBarItem - No definition found for type:', item.type, 'item:', item);
  }

  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: item.id });

  const style = {
    transform: CSS.Transform.toString(transform ? {...transform, x:transform.x / dragScale, y:transform.y / dragScale} : transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  if (!definition) {
    return (
      <div
        ref={setNodeRef}
        style={style}
        className={`touchbar-item unknown ${isSelected ? 'selected' : ''}`}
        onClick={onSelect}
        onContextMenu={onContextMenu}
      >
        <span className="touchbar-item-title">Unknown: {item.type}</span>
      </div>
    );
  }

  // Get display info
  const display = getItemDisplay(item, definition);

  // Determine if this is a slider type
  const isSlider = display.type === 'slider';

  // Determine if this is a group
  const isGroup = item.type === 'group';

  // Build class names
  const classNames = [
    'touchbar-item',
    `type-${item.type}`,
    isSelected ? 'selected' : '',
    isDragging ? 'dragging' : '',
    item.bordered === false ? 'no-border' : '',
    item.align ? `align-${item.align}` : '',
    isSlider ? 'slider' : '',
    isGroup ? 'group' : '',
    item.type === 'dock' && item.autoResize !== false ? 'auto-resized' : '',
  ].filter(Boolean).join(' ');

  // Inline styles for custom properties
  const itemStyle = {
    ...style,
    width: Number.isFinite(item.width) ? `${item.width}px` : undefined,
    background: item.background || undefined,
  };

  // Render content based on display type
  const renderContent = () => {
    if (display.type === 'resolve-color-dial') {
      const parameter = (item.parameter || 'lift').toUpperCase();
      const channel = item.channel || 'Y';
      const angle = ({Y:-32,R:-15,G:0,B:18})[channel] ?? 0;
      return (
        <div className="resolve-dial-preview" aria-hidden="true">
          <svg className="resolve-dial-ring" viewBox="0 0 20 20">
            <circle cx="10" cy="10" r="9" />
            <circle className="resolve-dial-track" cx="10" cy="10" r="6.8" />
            <line x1="10" y1="10" x2="10" y2="5" transform={`rotate(${angle} 10 10)`} />
            <circle className="resolve-dial-center" cx="10" cy="10" r="1.5" />
          </svg>
          <span className="resolve-dial-copy"><strong>{parameter} {channel}</strong><small>— · illustrative</small></span>
        </div>
      );
    }
    if (display.type === 'resolve-numeric-dial') {
      return (
        <div className="resolve-dial-preview" aria-hidden="true">
          <svg className="resolve-dial-ring" viewBox="0 0 20 20">
            <circle cx="10" cy="10" r="9" />
            <circle className="resolve-dial-track" cx="10" cy="10" r="6.8" />
            <line x1="10" y1="10" x2="10" y2="5" />
            <circle className="resolve-dial-center" cx="10" cy="10" r="1.5" />
          </svg>
          <span className="resolve-dial-copy"><strong>{item.title || 'HDR'}</strong><small>— · illustrative</small></span>
        </div>
      );
    }
    if (display.type === 'resolve-timeline-jog') {
      return (
        <div className="resolve-jog-preview" aria-hidden="true">
          <span className="resolve-jog-label">TIMELINE JOG</span>
          <span className="resolve-jog-track"><i /><b /></span>
          <span className="resolve-jog-caption">Relative · illustrative</span>
        </div>
      );
    }

    // Image display
    if (display.type === 'image') {
      return (
        <div className="touchbar-item-image">
          <img src={display.content} alt="" />
        </div>
      );
    }

    // Slider display
    if (display.type === 'slider') {
      return (
        <>
          <ControlIcon type={display.controlType} className="slider-icon" />
          <div className="slider-indicator">
            <div className="slider-track"></div>
          </div>
        </>
      );
    }

    // Dynamic values are illustrative labels, never fabricated live readings.
    if (display.type === 'sample') {
      return (
        <>
          <ControlIcon type={display.controlType} className="touchbar-icon" />
          <span className="touchbar-item-title">{display.content}</span>
        </>
      );
    }

    // Group display
    if (display.type === 'group') {
      return (
        <>
          <span className="touchbar-item-title">{display.content}</span>
          {display.count > 0 && (
            <span className="group-count">{display.count}</span>
          )}
        </>
      );
    }

    // Dock display
    if (display.type === 'dock') {
      const apps = item.dockApps || [];
      const iconSize = Number(item.dockIconSize) || 32;
      const {iconSize: fittedIconSize, itemSpacing: fittedItemSpacing} = fitDockIcons(
        Number.isFinite(item.width) ? item.width : 200,
        apps.length,
        iconSize,
        Number.isFinite(Number(item.dockItemSpacing)) ? Number(item.dockItemSpacing) : 1,
      );
      return (
        <div className="dock-preview" style={{gap: fittedItemSpacing}}>
          {apps.map(app => <img key={app.bundleId} className={`dock-app${app.running ? ' active' : ''}`} src={app.iconData} alt="" title={app.name} style={{width: fittedIconSize, height: fittedIconSize}} />)}
        </div>
      );
    }

    // Icon display
    if (display.type === 'icon') {
      return <ControlIcon type={display.controlType} className="touchbar-icon" />;
    }

    // Default text display
    return <span className="touchbar-item-title">{display.content}</span>;
  };

  return (
    <div
      ref={setNodeRef}
      style={itemStyle}
      className={classNames}
      onClick={onSelect}
      onContextMenu={onContextMenu}
      title={item.type === 'systemMonitor'
        ? `${item.runtimePreview ? 'Live readings from the current Touch Bar' : 'Illustrative preview only'}; selected readings: ${selectedSystemMonitorMetrics(item).map(metric => ({cpu:'CPU usage',gpu:'GPU usage',memory:'Memory usage',temperature:'CPU temperature'})[metric]).join(', ') || 'none'}`
        : ['cpu', 'ramUsage', 'gpuUsage', 'boardTemperature', 'cpuTemperature', 'resolveColorDial', 'resolveNumericDial', 'resolveTimelineJog'].includes(item.type) ? 'Illustrative preview only; no Resolve value is read in the editor' : undefined}
      {...attributes}
      {...listeners}
      aria-label={`${definition.label}${item.title ? `: ${item.title}` : item.type === 'systemMonitor' ? `: ${selectedSystemMonitorMetrics(item).join(', ') || 'icon only'}` : ''} — ${item.type === 'systemMonitor' && item.runtimePreview ? 'live readings from the current Touch Bar' : 'editor preview'}`}
    >
      {renderContent()}
      {isSelected && <div className="selection-indicator" />}
    </div>
  );
}
