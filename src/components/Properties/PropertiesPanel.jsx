import { useState, useEffect } from 'react';
import { useApp } from '../../context/AppContext';
import { getElementDefinition, commonProperties, actionTypes, actionTriggers } from '../../data/elementDefinitions';
import './Properties.css';
import {BAR_WIDTH,contentFitWidth,contentMinimumWidth,clampPosition,layoutContentScale} from '../../utils/positionLayout';
import {SYSTEM_MONITOR_METRICS, selectedSystemMonitorMetrics} from '../../utils/systemMonitor';
import {systemMonitorWidthForSelection,widgetWidthForContent} from '../../utils/widgetSizing';
import {getControlInfo} from '../../data/controlCatalog';
import { getControlStatus } from '../../data/controlAvailability';
import { useRuntimePermissions } from '../../context/useRuntimePermissions';
import {matchSystemMonitorRuntimePreviews} from '../../utils/systemMonitorRuntimePreview.js';

const shortcutKeys = [
  ['A', 0], ['B', 11], ['C', 8], ['D', 2], ['E', 14], ['F', 3], ['G', 5], ['H', 4],
  ['I', 34], ['J', 38], ['K', 40], ['L', 37], ['M', 46], ['N', 45], ['O', 31], ['P', 35],
  ['Q', 12], ['R', 15], ['S', 1], ['T', 17], ['U', 32], ['V', 9], ['W', 13], ['X', 7],
  ['Y', 16], ['Z', 6], ['Left Arrow', 123], ['Right Arrow', 124], ['Down Arrow', 125],
  ['Up Arrow', 126], ['Home', 115], ['End', 119], ['Space', 49], ['Return', 36], ['Tab', 48], ['Escape', 53],
].map(([label, keycode]) => ({ label, value: String(keycode) }));

export default function PropertiesPanel() {
  const { getSelectedItem, updateItem, removeItem, selectedItemId, enterGroup, combineSystemMonitor, profiles, profileId, resolvePageId, groupPath } = useApp();
  const { accessibilityAccess, layoutCapacity, systemMonitorPreviews, activeStudioGroupPath, activeRuntimeProfile, activeRuntimeResolvePage, activeRuntimeEnabled } = useRuntimePermissions();
  const item = getSelectedItem();
  const liveMonitorPreview = item?.type === 'systemMonitor' && item.autoFitContent
    ? matchSystemMonitorRuntimePreviews({rows:systemMonitorPreviews,profiles,profileId,resolvePageId,groupPath,activeProfile:activeRuntimeProfile,activeResolvePage:activeRuntimeResolvePage,activeGroupPath:activeStudioGroupPath,runtimeEnabled:activeRuntimeEnabled}).get(item.id)
    : null;
  const definition = item ? getElementDefinition(item.type) : null;
  const control = item ? getControlInfo(item.type, item) : null;
  const fittedWidth = item ? contentFitWidth(item) : 0;
  const canFitToContent = item && ['timeButton','systemMonitor'].includes(item.type);
  const contentScale = layoutContentScale(layoutCapacity, {
    submenu: groupPath.length > 0,
    resolveProfile: profiles[profileId]?.bundleId === 'com.blackmagic-design.DaVinciResolve',
  }) || 1;

  if (!item || !definition) {
    return (
      <div className="properties-panel">
        <div className="properties-header">
          <h2>Properties</h2>
        </div>
        <div className="properties-empty">
          <p>Select an element to edit its properties</p>
        </div>
      </div>
    );
  }

  return (
    <div className="properties-panel">
      <div className="properties-header">
        <h2>Properties</h2>
        <span className="properties-type">{control?.label || definition.label}</span>
      </div>
      <div className="properties-content">
        {control && <section className="control-runtime-note" aria-label="Control availability"><strong>{getControlStatus(control, accessibilityAccess)}</strong><p>{control.benefit}</p></section>}

        <PropertySection title="Placement">
          <PropertyInput label="X position (0–1085)" type="number" value={item.studioPosition ?? ''} placeholder="Automatic" onChange={value=>updateItem(item.id,{studioPosition:value===''?undefined:clampPosition(value,fittedWidth)})}/>
          <p className="placement-help">Set an exact leading edge, or use Precise placement above the preview. Drag controls along the ruler.</p>
          {Number.isFinite(item.studioPosition)&&<input aria-label="Position on Touch Bar" type="range" min="0" max={Math.max(0,BAR_WIDTH-fittedWidth)} step="1" value={Math.min(item.studioPosition,Math.max(0,BAR_WIDTH-fittedWidth))} onChange={e=>updateItem(item.id,{studioPosition:+e.target.value})}/>}
        </PropertySection>
        {/* Common Properties */}
        <PropertySection title="General">
          <PropertyInput
            label="Width"
            type="number"
            value={item.autoFitContent && item.type === 'systemMonitor' ? '' : item.width || ''}
            onChange={(value) => {
              const width=value ? Math.min(1085,Math.max(24,Number(value))) : undefined;
              updateItem(item.id,{width,...(item.type === 'systemMonitor'?{autoFitContent:false}:{}),...(Number.isFinite(item.studioPosition)?{studioPosition:clampPosition(item.studioPosition,Math.max(width||64,contentMinimumWidth(item)))}:{})});
            }}
            placeholder={item.autoFitContent && item.type === 'systemMonitor' ? 'Live' : 'Auto'}
            action={canFitToContent ? <button type="button" className="fit-content-button" onClick={() => {
              if (item.type === 'systemMonitor') updateItem(item.id,{width:null,autoFitContent:true});
              else {
                const width=widgetWidthForContent(item,contentScale);
                updateItem(item.id,{width,...(Number.isFinite(item.studioPosition)?{studioPosition:clampPosition(item.studioPosition,width)}:{})});
              }
            }}>{item.type === 'systemMonitor' ? 'Fit live content' : 'Fit to content'}</button> : null}
          />
          {item.type === 'systemMonitor' && item.autoFitContent && <p className="placement-help" role="status">{liveMonitorPreview ? `Live on Touch Bar · ${Math.round(liveMonitorPreview.frameWidth)} pt current frame` : 'Illustrative preview · Live readings appear when this saved bar is active.'}</p>}
          {Number.isFinite(item.width) && item.width < fittedWidth && <p className="placement-help">This control needs about {Math.ceil(fittedWidth)} units for its full content. The preview grows to fit; it may overlap nearby controls.</p>}
          <PropertySelect
            label="Alignment"
            value={item.align || 'center'}
            options={[
              { value: 'left', label: 'Left' },
              { value: 'center', label: 'Center' },
              { value: 'right', label: 'Right' },
            ]}
            onChange={(value) => updateItem(item.id, { align: value })}
          />
          <PropertyToggle
            label="Bordered"
            value={item.bordered !== false}
            onChange={(value) => updateItem(item.id, { bordered: value })}
          />
          <PropertyInput
            label="Background"
            type="color"
            value={item.background || '#000000'}
            onChange={(value) => updateItem(item.id, { background: value || undefined })}
          />
          <PropertyInput
            label="Match App ID"
            type="text"
            value={item.matchAppId || ''}
            onChange={(value) => updateItem(item.id, { matchAppId: value || undefined })}
            placeholder="e.g., Safari"
          />
        </PropertySection>

        {/* Title Property */}
        <PropertySection title="Title & Image">
          <PropertyInput
            label="Title"
            type="text"
            value={item.title || ''}
            onChange={(value) => updateItem(item.id, { title: value || undefined })}
            placeholder="Button text"
          />
          <PropertyImage
            value={item.image}
            onChange={(value) => updateItem(item.id, { image: value })}
          />
        </PropertySection>

        {/* Type-Specific Properties */}
        {definition.properties && definition.properties.length > 0 && (
          <PropertySection title="Type Settings">
            <TypeSpecificProperties item={item} definition={definition} updateItem={updateItem} enterGroup={enterGroup} contentScale={contentScale} />
          </PropertySection>
        )}

        {['cpu','ramUsage','gpuUsage','cpuTemperature'].includes(item.type) && (
          <section className="property-section">
            <h3 className="property-section-title">System monitor</h3>
            <div className="property-section-content">
              <p className="placement-help">Combine metric widgets in this layout into one compact control. You can undo this change.</p>
              <button className="combine-monitor-button" onClick={() => combineSystemMonitor(item.id,{contentScale})}>Combine into System Monitor</button>
            </div>
          </section>
        )}

        {/* Actions */}
        {definition.supportsActions && (
          <PropertySection title="Actions">
            <p className="placement-help">Keyboard actions use macOS Accessibility access. Shell and AppleScript actions are kept for export and do not run in this app.</p>
            <ActionsEditor item={item} updateItem={updateItem} />
          </PropertySection>
        )}

        {/* Delete Button */}
        <div className="properties-actions">
          <button
            className="delete-button"
            onClick={() => removeItem(item.id)}
          >
            Delete Element
          </button>
        </div>
      </div>
    </div>
  );
}

function PropertySection({ title, children }) {
  return (
    <div className="property-section">
      <h3 className="property-section-title">{title}</h3>
      <div className="property-section-content">
        {children}
      </div>
    </div>
  );
}

function PropertyInput({ label, type, value, onChange, placeholder, action }) {
  return (
    <div className="property-field">
      <label className="property-label">{label}</label>
      <div className={action ? 'property-input-row with-action' : 'property-input-row'}>
        <input
          type={type}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          className="property-input"
        />
        {action}
      </div>
    </div>
  );
}

function PropertySelect({ label, value, options, onChange }) {
  return (
    <div className="property-field">
      <label className="property-label">{label}</label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="property-select"
      >
        {options.map((opt) => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </select>
    </div>
  );
}

function PropertyToggle({ label, value, onChange }) {
  return (
    <div className="property-field property-toggle">
      <label className="property-label">{label}</label>
      <button
        className={`toggle-button ${value ? 'active' : ''}`}
        onClick={() => onChange(!value)}
      >
        {value ? 'On' : 'Off'}
      </button>
    </div>
  );
}

function PropertyImage({ value, onChange }) {
  const [mode, setMode] = useState('none'); // 'none', 'base64', 'filePath'

  useEffect(() => {
    if (!value) setMode('none');
    else if (value.base64) setMode('base64');
    else if (value.filePath) setMode('filePath');
  }, [value]);

  const handleFileChange = (e) => {
    const file = e.target.files?.[0];
    if (file) {
      const reader = new FileReader();
      reader.onloadend = () => {
        const base64 = reader.result.split(',')[1];
        onChange({ base64 });
      };
      reader.readAsDataURL(file);
    }
  };

  return (
    <div className="property-field">
      <label className="property-label">Image</label>
      <div className="image-inputs">
        <select
          value={mode}
          onChange={(e) => {
            setMode(e.target.value);
            if (e.target.value === 'none') onChange(null);
          }}
          className="property-select"
        >
          <option value="none">None</option>
          <option value="base64">Upload Image</option>
          <option value="filePath">File Path</option>
        </select>
        
        {mode === 'base64' && (
          <div className="image-upload">
            <input
              type="file"
              accept="image/*"
              onChange={handleFileChange}
              className="property-file-input"
            />
            {value?.base64 && (
              <img
                src={`data:image/png;base64,${value.base64}`}
                alt="Preview"
                className="image-preview"
              />
            )}
          </div>
        )}
        
        {mode === 'filePath' && (
          <input
            type="text"
            value={value?.filePath || ''}
            onChange={(e) => onChange({ filePath: e.target.value })}
            placeholder="~/path/to/image.png"
            className="property-input"
          />
        )}
      </div>
    </div>
  );
}

function TypeSpecificProperties({ item, definition, updateItem, enterGroup, contentScale = 1 }) {
  const type = item.type;

  switch (type) {
    case 'systemMonitor': {
      const selected = selectedSystemMonitorMetrics(item);
      const labels = {cpu:'CPU usage',gpu:'GPU usage',memory:'Memory usage',temperature:'CPU temperature'};
      return (
        <fieldset className="system-monitor-options">
          <legend>Show readings</legend>
          {SYSTEM_MONITOR_METRICS.map(metric => (
            <label key={metric}>
              <input type="checkbox" checked={selected.includes(metric)} onChange={event => {
                const next = event.target.checked ? [...selected, metric] : selected.filter(value => value !== metric);
                const metrics = SYSTEM_MONITOR_METRICS.filter(value => next.includes(value));
                const width = systemMonitorWidthForSelection(metrics,contentScale);
                updateItem(item.id, {metrics,...(item.autoFitContent?{width:null}:{width}),...(!item.autoFitContent&&Number.isFinite(item.studioPosition) ? {studioPosition:clampPosition(item.studioPosition,width)} : {})});
              }} />
              <span>{labels[metric]}</span>
            </label>
          ))}
          <p className="placement-help">Readings stay in CPU, GPU, Memory, Temperature order. Clear every box to show the icon alone.</p>
        </fieldset>
      );
    }

    case 'timeButton':
      return (
        <>
          <PropertyInput
            label="Format Template"
            type="text"
            value={item.formatTemplate || ''}
            onChange={(value) => updateItem(item.id, { formatTemplate: value })}
            placeholder="HH:mm"
          />
          <PropertyInput
            label="Locale"
            type="text"
            value={item.locale || ''}
            onChange={(value) => updateItem(item.id, { locale: value })}
            placeholder="en_US"
          />
          <PropertyInput
            label="Time Zone"
            type="text"
            value={item.timeZone || ''}
            onChange={(value) => updateItem(item.id, { timeZone: value })}
            placeholder="UTC"
          />
        </>
      );

    case 'currency':
      return (
        <>
          <PropertyInput
            label="Refresh Interval (s)"
            type="number"
            value={item.refreshInterval || ''}
            onChange={(value) => updateItem(item.id, { refreshInterval: value ? Number(value) : undefined })}
          />
          <PropertyInput
            label="From Currency"
            type="text"
            value={item.from || ''}
            onChange={(value) => updateItem(item.id, { from: value })}
            placeholder="BTC"
          />
          <PropertyInput
            label="To Currency"
            type="text"
            value={item.to || ''}
            onChange={(value) => updateItem(item.id, { to: value })}
            placeholder="USD"
          />
          <PropertyToggle
            label="Full Format"
            value={item.full || false}
            onChange={(value) => updateItem(item.id, { full: value })}
          />
        </>
      );

    case 'weather':
      return (
        <>
          <PropertyInput
            label="Refresh Interval (s)"
            type="number"
            value={item.refreshInterval || ''}
            onChange={(value) => updateItem(item.id, { refreshInterval: value ? Number(value) : undefined })}
          />
          <PropertySelect
            label="Units"
            value={item.units || 'imperial'}
            options={[
              { value: 'imperial', label: 'Imperial (°F)' },
              { value: 'metric', label: 'Metric (°C)' },
            ]}
            onChange={(value) => updateItem(item.id, { units: value })}
          />
          <PropertySelect
            label="Icon Type"
            value={item.icon_type || 'text'}
            options={[
              { value: 'text', label: 'Text' },
              { value: 'images', label: 'Images' },
            ]}
            onChange={(value) => updateItem(item.id, { icon_type: value })}
          />
          <PropertyInput
            label="API Key"
            type="text"
            value={item.api_key || ''}
            onChange={(value) => updateItem(item.id, { api_key: value })}
            placeholder="OpenWeather API key"
          />
        </>
      );

    case 'yandexWeather':
    case 'music':
      return (
        <>
          <PropertyInput
            label="Refresh Interval (s)"
            type="number"
            value={item.refreshInterval || ''}
            onChange={(value) => updateItem(item.id, { refreshInterval: value ? Number(value) : undefined })}
          />
          {type === 'music' && (
            <PropertyToggle
              label="Disable Marquee"
              value={item.disableMarquee || false}
              onChange={(value) => updateItem(item.id, { disableMarquee: value })}
            />
          )}
        </>
      );

    case 'dock':
      return (
        <>
          <PropertyInput
            label="Filter (Regex)"
            type="text"
            value={item.filter || ''}
            onChange={(value) => updateItem(item.id, { filter: value })}
            placeholder="(^Xcode$)|(Safari)"
          />
          <PropertyToggle
            label="Auto Resize"
            value={item.autoResize || false}
            onChange={(value) => updateItem(item.id, { autoResize: value })}
          />
        </>
      );

    case 'pomodoro':
      return (
        <>
          <PropertyInput
            label="Work Time (s)"
            type="number"
            value={item.workTime || ''}
            onChange={(value) => updateItem(item.id, { workTime: value ? Number(value) : undefined })}
          />
          <PropertyInput
            label="Rest Time (s)"
            type="number"
            value={item.restTime || ''}
            onChange={(value) => updateItem(item.id, { restTime: value ? Number(value) : undefined })}
          />
        </>
      );

    case 'network':
      return (
        <>
          <PropertyToggle
            label="Flip"
            value={item.flip || false}
            onChange={(value) => updateItem(item.id, { flip: value })}
          />
          <PropertySelect
            label="Units"
            value={item.units || 'dynamic'}
            options={[
              { value: 'dynamic', label: 'Dynamic' },
              { value: 'B/s', label: 'B/s' },
              { value: 'KB/s', label: 'KB/s' },
              { value: 'MB/s', label: 'MB/s' },
              { value: 'GB/s', label: 'GB/s' },
            ]}
            onChange={(value) => updateItem(item.id, { units: value })}
          />
        </>
      );

    case 'upnext':
      return (
        <>
          <PropertyInput
            label="From (hours)"
            type="number"
            value={item.from ?? ''}
            onChange={(value) => updateItem(item.id, { from: value ? Number(value) : 0 })}
          />
          <PropertyInput
            label="To (hours)"
            type="number"
            value={item.to ?? ''}
            onChange={(value) => updateItem(item.id, { to: value ? Number(value) : 12 })}
          />
          <PropertyInput
            label="Max to Show"
            type="number"
            value={item.maxToShow ?? ''}
            onChange={(value) => updateItem(item.id, { maxToShow: value ? Number(value) : 3 })}
          />
          <PropertyToggle
            label="Auto Resize"
            value={item.autoResize || false}
            onChange={(value) => updateItem(item.id, { autoResize: value })}
          />
        </>
      );

    case 'staticButton':
      return (
        <PropertyInput
          label="Title"
          type="text"
          value={item.title || ''}
          onChange={(value) => updateItem(item.id, { title: value })}
          placeholder="Button text"
        />
      );

    case 'appleScriptTitledButton':
    case 'shellScriptTitledButton':
      return (
        <>
          <SourceEditor
            label="Source"
            value={item.source}
            onChange={(value) => updateItem(item.id, { source: value })}
          />
          <PropertyInput
            label="Refresh Interval (s)"
            type="number"
            value={item.refreshInterval || ''}
            onChange={(value) => updateItem(item.id, { refreshInterval: value ? Number(value) : undefined })}
          />
          {type === 'appleScriptTitledButton' && (
            <AlternativeImagesEditor
              value={item.alternativeImages || {}}
              onChange={(value) => updateItem(item.id, { alternativeImages: value })}
            />
          )}
        </>
      );

    case 'swipe':
      return (
        <>
          <PropertySelect
            label="Fingers"
            value={item.fingers || 2}
            options={[
              { value: 2, label: '2 Fingers' },
              { value: 3, label: '3 Fingers' },
              { value: 4, label: '4 Fingers' },
            ]}
            onChange={(value) => updateItem(item.id, { fingers: Number(value) })}
          />
          <PropertySelect
            label="Direction"
            value={item.direction || 'right'}
            options={[
              { value: 'left', label: 'Left' },
              { value: 'right', label: 'Right' },
            ]}
            onChange={(value) => updateItem(item.id, { direction: value })}
          />
          <PropertyInput
            label="Min Offset"
            type="number"
            value={item.minOffset || ''}
            onChange={(value) => updateItem(item.id, { minOffset: value ? Number(value) : undefined })}
          />
          <SourceEditor
            label="Apple Script"
            value={item.sourceApple}
            onChange={(value) => updateItem(item.id, { sourceApple: value })}
          />
          <SourceEditor
            label="Shell Script"
            value={item.sourceBash}
            onChange={(value) => updateItem(item.id, { sourceBash: value })}
          />
        </>
      );

    case 'group':
      return (
        <>
          <PropertyInput
            label="Title"
            type="text"
            value={item.title || ''}
            onChange={(value) => updateItem(item.id, { title: value })}
            placeholder="Group name"
          />
          <button type="button" onClick={() => enterGroup(item.id)}>Open submenu</button>
        </>
      );

    default:
      return <p className="no-properties">No additional properties</p>;
  }
}

function SourceEditor({ label, value, onChange }) {
  const [mode, setMode] = useState(value?.inline ? 'inline' : value?.filePath ? 'filePath' : 'inline');

  return (
    <div className="property-field source-editor">
      <label className="property-label">{label}</label>
      <select
        value={mode}
        onChange={(e) => {
          setMode(e.target.value);
          onChange({ [e.target.value]: '' });
        }}
        className="property-select"
      >
        <option value="inline">Inline</option>
        <option value="filePath">File Path</option>
        <option value="base64">Base64</option>
      </select>
      <textarea
        value={value?.[mode] || ''}
        onChange={(e) => onChange({ [mode]: e.target.value })}
        placeholder={mode === 'inline' ? 'Enter script...' : mode === 'filePath' ? '~/path/to/script' : 'Base64 encoded...'}
        className="property-textarea"
        rows={4}
      />
    </div>
  );
}

function AlternativeImagesEditor({ value, onChange }) {
  const [newKey, setNewKey] = useState('');

  const addImage = () => {
    if (newKey) {
      onChange({ ...value, [newKey]: { base64: '' } });
      setNewKey('');
    }
  };

  const removeImage = (key) => {
    const newValue = { ...value };
    delete newValue[key];
    onChange(newValue);
  };

  return (
    <div className="property-field alternative-images">
      <label className="property-label">Alternative Images</label>
      <div className="alt-images-list">
        {Object.entries(value).map(([key, img]) => (
          <div key={key} className="alt-image-item">
            <span className="alt-image-key">{key}</span>
            <button
              className="remove-alt-image"
              onClick={() => removeImage(key)}
            >
              ×
            </button>
          </div>
        ))}
      </div>
      <div className="add-alt-image">
        <input
          type="text"
          value={newKey}
          onChange={(e) => setNewKey(e.target.value)}
          placeholder="Image label"
          className="property-input"
        />
        <button onClick={addImage} className="add-button">Add</button>
      </div>
    </div>
  );
}

function ActionsEditor({ item, updateItem }) {
  const actions = item.actions || [];

  const addAction = () => {
    const newAction = {
      id: `action-${Date.now()}`,
      trigger: 'singleTap',
      action: 'hidKey',
      keycode: 0,
    };
    updateItem(item.id, { actions: [...actions, newAction] });
  };

  const updateAction = (actionId, updates) => {
    updateItem(item.id, {
      actions: actions.map((a) => (a.id === actionId ? { ...a, ...updates } : a)),
    });
  };

  const removeAction = (actionId) => {
    updateItem(item.id, {
      actions: actions.filter((a) => a.id !== actionId),
    });
  };

  return (
    <div className="actions-editor">
      {actions.map((action) => (
        <ActionItem
          key={action.id}
          action={action}
          onUpdate={(updates) => updateAction(action.id, updates)}
          onRemove={() => removeAction(action.id)}
        />
      ))}
      <button onClick={addAction} className="add-action-button">
        + Add Action
      </button>
    </div>
  );
}

function ActionItem({ action, onUpdate, onRemove }) {
  return (
    <div className="action-item">
      <div className="action-header">
        <select
          value={action.trigger}
          onChange={(e) => onUpdate({ trigger: e.target.value })}
          className="property-select small"
        >
          {actionTriggers.map((t) => (
            <option key={t.value} value={t.value}>
              {t.label}
            </option>
          ))}
        </select>
        <select
          value={action.action}
          onChange={(e) => onUpdate({ action: e.target.value })}
          className="property-select small"
        >
          {Object.values(actionTypes).map((t) => (
            <option key={t.type} value={t.type}>
              {t.label}
            </option>
          ))}
        </select>
        <button onClick={onRemove} className="remove-action-button">×</button>
      </div>
      
      <div className="action-params">
        {action.action === 'hidKey' && (
          <PropertyInput
            label="Keycode"
            type="number"
            value={action.keycode || 0}
            onChange={(value) => onUpdate({ keycode: Number(value) })}
          />
        )}
        {action.action === 'keyPress' && (
          <>
            <PropertySelect
              label="Shortcut key"
              value={shortcutKeys.some((key) => Number(key.value) === Number(action.keycode)) ? String(action.keycode) : `other-${action.keycode}`}
              options={[
                ...shortcutKeys,
                ...(!shortcutKeys.some((key) => Number(key.value) === Number(action.keycode))
                  ? [{ label: `Other key (${action.keycode ?? 0})`, value: `other-${action.keycode ?? 0}` }]
                  : []),
              ]}
              onChange={(value) => onUpdate({ keycode: Number(value.replace('other-', '')) })}
            />
            <PropertyInput label="Keycode" type="number" value={action.keycode ?? 0} onChange={(value) => onUpdate({ keycode: Number(value) })} />
            <fieldset className="shortcut-modifiers"><legend>Modifier keys</legend>{[['command','Command'],['option','Option'],['shift','Shift'],['control','Control']].map(([key,label])=><label key={key}><input type="checkbox" checked={(action.modifiers||[]).includes(key)} onChange={event=>{const next=new Set(action.modifiers||[]);if(event.target.checked)next.add(key);else next.delete(key);onUpdate({modifiers:[...next]});}}/>{label}</label>)}</fieldset>
          </>
        )}
        {action.action === 'appleScript' && (
          <SourceEditor
            label="Script"
            value={action.actionAppleScript}
            onChange={(value) => onUpdate({ actionAppleScript: value })}
          />
        )}
        {action.action === 'shellScript' && (
          <>
            <PropertyInput
              label="Executable Path"
              type="text"
              value={action.executablePath || ''}
              onChange={(value) => onUpdate({ executablePath: value })}
            />
            <PropertyInput
              label="Arguments"
              type="text"
              value={action.shellArguments?.join(' ') || ''}
              onChange={(value) => onUpdate({ shellArguments: value ? value.split(' ') : undefined })}
            />
          </>
        )}
        {action.action === 'openUrl' && (
          <PropertyInput
            label="URL"
            type="text"
            value={action.url || ''}
            onChange={(value) => onUpdate({ url: value })}
          />
        )}
      </div>
    </div>
  );
}
