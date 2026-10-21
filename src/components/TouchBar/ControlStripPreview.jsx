import ControlIcon from '../ControlIcon/ControlIcon';

function PreviewButton({ type, label, glyph }) {
  return (
    <span className="control-strip-static-button" role="img" aria-label={`${label} button preview`}>
      {type ? <ControlIcon type={type} className="control-strip-icon" /> : <span className={label === 'Siri' ? 'control-strip-siri' : ''} aria-hidden="true">{glyph}</span>}
    </span>
  );
}

export default function ControlStripPreview({ expanded, onExpand, onCollapse }) {
  if (expanded) {
    return (
      <div className="control-strip-expanded" role="group" aria-label="Expanded macOS Control Strip preview. Preview only; these controls do not change your Mac.">
        <button className="control-strip-collapse" onClick={onCollapse} aria-expanded="true" aria-label="Collapse macOS Control Strip preview" title="Collapse Control Strip">×</button>
        <div className="control-strip-expanded-controls">
          <PreviewButton type="brightnessDown" label="Decrease display brightness" />
          <PreviewButton type="brightnessUp" label="Increase display brightness" />
          <PreviewButton label="Mission Control" glyph="▱" />
          <PreviewButton label="Launchpad" glyph="▦" />
          <PreviewButton type="illuminationDown" label="Decrease keyboard illumination" />
          <PreviewButton type="illuminationUp" label="Increase keyboard illumination" />
          <PreviewButton type="previous" label="Previous track" />
          <PreviewButton type="play" label="Play or pause" />
          <PreviewButton type="next" label="Next track" />
          <PreviewButton type="mute" label="Mute" />
          <PreviewButton type="volumeDown" label="Lower volume" />
          <PreviewButton type="volumeUp" label="Raise volume" />
          <PreviewButton label="Siri" glyph="●" />
        </div>
        <span className="control-strip-preview-note">Preview only</span>
      </div>
    );
  }

  return (
    <div className="control-strip-compact touchbar-item type-control-strip" role="group" aria-label="Collapsed macOS Control Strip preview. Preview only; controls are shown for layout context.">
      <button className="control-strip-expand" onClick={onExpand} aria-expanded="false" aria-label="Expand macOS Control Strip preview" title="Expand Control Strip">‹</button>
      <span role="img" aria-label="Display brightness preview"><ControlIcon type="brightness" className="control-strip-icon" /></span>
      <span role="img" aria-label="Volume preview"><ControlIcon type="volume" className="control-strip-icon" /></span>
      <span role="img" aria-label="Mute preview"><ControlIcon type="mute" className="control-strip-icon" /></span>
      <span className="control-strip-siri" role="img" aria-label="Siri preview">●</span>
    </div>
  );
}
