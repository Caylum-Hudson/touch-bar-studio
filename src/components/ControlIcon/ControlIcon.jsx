import { useState } from 'react';
import './ControlIcon.css';

const glyphs = {
  escape: 'esc', delete: '⌫', volumeUp: '◖', volumeDown: '◗', mute: '◖', volume: '◖',
  previous: '◂|', play: '▶', next: '|▸', brightnessUp: '☼', brightnessDown: '☼', brightness: '☼',
  illuminationUp: '⌨', illuminationDown: '⌨', timeButton: '◷', dateButton: '▦', battery: '▰',
  inputsource: '⌘', music: '♫', darkMode: '◐', nightShift: '◔', dnd: '◉', pomodoro: '◴', cpu: '▣',
  dock: '▤', exitTouchbar: '↙', network: '⌁', weather: '☼', yandexWeather: '☼', currency: '↔',
  upnext: '▦', ramUsage: '▤', gpuUsage: '▭', boardTemperature: '°C', cpuTemperature: '°C', staticButton: '●', appleScriptTitledButton: '⌘', shellScriptTitledButton: '$',
  group: '▣', close: '×', swipe: '↔', sleep: '◌', displaySleep: '◉',
};

export default function ControlIcon({ type, className = '' }) {
  const [missingType, setMissingType] = useState(null);
  const missing = missingType === type;
  const fallback = glyphs[type] || '•';
  if (missing) return <span className={`control-icon ${className}`} aria-hidden="true">{fallback}</span>;
  return <img className={`control-icon ${className}`} src={`/control-icons/${type}.png`} alt="" aria-hidden="true" onError={() => setMissingType(type)} />;
}
