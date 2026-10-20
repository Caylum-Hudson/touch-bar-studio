import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { getElementDefinition } from '../../data/elementDefinitions';
import ControlIcon from '../ControlIcon/ControlIcon';
import './TouchBar.css';

// Get display content for an item based on its type
function getItemDisplay(item, definition) {
  const type = item.type;

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
      return { type: 'sample', controlType: type, content: getCurrentTime(item.formatTemplate, item.timeZone) };
    case 'weather':
    case 'yandexWeather':
      return { type: 'sample', controlType: type, content: 'Weather' };
    case 'cpu':
      return { type: 'sample', controlType: type, content: 'CPU' };
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

// Get current time formatted
function getCurrentTime(format, timeZone) {
  if (!format) {
    format = 'HH:mm';
  }

  // Parse custom prefix from format (e.g., "'🌉' h:mm a" -> prefix='🌉', format='h:mm a')
  let prefix = '';
  let actualFormat = format;

  const quotedMatch = format.match(/^'([^']*)'[\s]+(.*)/);
  if (quotedMatch) {
    prefix = quotedMatch[1];
    actualFormat = quotedMatch[2];
  }

  // Get current time in the target timezone
  let now;
  if (timeZone && timeZone.trim()) {
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    });

    const parts = formatter.formatToParts(new Date());
    const obj = {};
    parts.forEach(p => {
      if (p.type !== 'literal') obj[p.type] = p.value;
    });

    now = new Date(`${obj.year}-${obj.month}-${obj.day}T${obj.hour}:${obj.minute}:${obj.second}`);
  } else {
    now = new Date();
  }

  // Time components
  const h24 = now.getHours();
  const h12 = h24 % 12 || 12;
  const minutes = now.getMinutes();
  const seconds = now.getSeconds();
  const mm = minutes.toString().padStart(2, '0');
  const ss = seconds.toString().padStart(2, '0');
  const H = h24.toString();
  const HH = h24.toString().padStart(2, '0');
  const h = h12.toString();
  const hh = h12.toString().padStart(2, '0');
  const a = h24 >= 12 ? 'pm' : 'am';
  const A = h24 >= 12 ? 'PM' : 'AM';
  const aa = h24 >= 12 ? 'pm' : 'am';

  // Date components
  const day = now.getDate();
  const month = now.getMonth();
  const year = now.getFullYear();
  const dayOfWeek = now.getDay();

  const d = day.toString();
  const dd = day.toString().padStart(2, '0');
  const M = (month + 1).toString();
  const MM = (month + 1).toString().padStart(2, '0');
  const yy = year.toString().slice(-2);
  const yyyy = year.toString();

  // Month names
  const monthNamesShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const monthNamesFull = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const MMM = monthNamesShort[month];
  const MMMM = monthNamesFull[month];

  // Day names
  const dayNamesShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const dayNamesFull = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const EEE = dayNamesShort[dayOfWeek];
  const EEEE = dayNamesFull[dayOfWeek];

  // Build time string from format
  // Order matters: longer patterns must be replaced first
  let timeStr = actualFormat
    // Date tokens (longer patterns first)
    .replace(/EEEE/g, EEEE)
    .replace(/EEE/g, EEE)
    .replace(/MMMM/g, MMMM)
    .replace(/MMM/g, MMM)
    .replace(/yyyy/g, yyyy)
    .replace(/yy/g, yy)
    .replace(/MM/g, MM)
    .replace(/M(?!M)/g, M)
    .replace(/dd/g, dd)
    .replace(/d(?!d)/g, d)
    // Time tokens
    .replace(/HH/g, HH)
    .replace(/H(?!H)/g, H)
    .replace(/hh/g, hh)
    .replace(/h(?!h)/g, h)
    .replace(/mm/g, mm)
    .replace(/ss/g, ss)
    .replace(/aa/g, aa)
    .replace(/a/g, a)
    .replace(/A/g, A);

  return prefix ? `${prefix} ${timeStr}` : timeStr;
}

export default function TouchBarItem({ item, isSelected, onSelect, onContextMenu }) {
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
    transform: CSS.Transform.toString(transform),
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
  ].filter(Boolean).join(' ');

  // Inline styles for custom properties
  const itemStyle = {
    ...style,
    width: item.width ? `${item.width}px` : undefined,
    background: item.background || undefined,
  };

  // Render content based on display type
  const renderContent = () => {
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
      return (
        <div className="dock-preview">
          <ControlIcon type="dock" className="dock-app" />
          <ControlIcon type="music" className="dock-app" />
          <ControlIcon type="network" className="dock-app" />
          <ControlIcon type="staticButton" className="dock-app active" />
          <ControlIcon type="group" className="dock-app" />
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
      {...attributes}
      {...listeners}
      aria-label={`${definition.label}${item.title ? `: ${item.title}` : ''} — editor preview`}
    >
      {renderContent()}
      {isSelected && <div className="selection-indicator" />}
    </div>
  );
}
