import { elementTypes } from './elementDefinitions.js';

// Curated palette order and guidance. `key` preserves aliases such as Date Button.
const commonGroups = [
  {
    id: 'sound-media', label: 'Sound & media', description: 'Control playback and listening level.',
    controls: [
      ['volumeUp', 'Permission needed', 'Raise system volume.'], ['volumeDown', 'Permission needed', 'Lower system volume.'],
      ['mute', 'Permission needed', 'Toggle system mute.'], ['volume', 'Hardware dependent', 'Tap to open a full-bar volume slider.'],
      ['previous', 'Permission needed', 'Go to the previous track.'], ['play', 'Permission needed', 'Play or pause media.'], ['next', 'Permission needed', 'Skip to the next track.'],
    ],
  },
  {
    id: 'display-keyboard', label: 'Display & keyboard', description: 'Adjust screen and keyboard lighting.',
    controls: [
      ['brightnessUp', 'Permission + hardware', 'Increase display brightness.'], ['brightnessDown', 'Permission + hardware', 'Decrease display brightness.'],
      ['brightness', 'Hardware dependent', 'Tap to open a full-bar brightness slider.'], ['illuminationUp', 'Permission + hardware', 'Increase keyboard backlight.'],
      ['illuminationDown', 'Permission + hardware', 'Decrease keyboard backlight.'],
    ],
  },
  {
    id: 'time-status', label: 'Time & status', description: 'Show useful information at a glance.',
    controls: [
      ['timeButton', 'Built in', 'Show the current time.'], ['dateButton', 'Built in', 'Show today’s date.'], ['battery', 'Built in', 'Show battery status.'],
      ['inputsource', 'Built in', 'Show the active input source.'], ['pomodoro', 'Built in', 'Start a focus timer.'],
      ['cpu', 'Local display · Automation on tap', 'Show CPU load locally; tapping Activity Monitor needs Automation access.'],
    ],
  },
  {
    id: 'navigation', label: 'Navigation', description: 'Move around or open useful system surfaces.',
    controls: [
      ['escape', 'Permission needed', 'Send the Escape key.'], ['delete', 'Permission needed', 'Send the forward Delete key.'], ['dock', 'Built in', 'Show Dock apps.'],
      ['exitTouchbar', 'Built in', 'Dismiss the Touch Bar.'], ['group', 'Built in', 'Create a submenu for related controls.'],
    ],
  },
];

const advancedGroups = [
  {
    id: 'advanced-status', label: 'Network & connected services', description: 'These controls depend on external services or system data.',
    controls: [
      ['network', 'Needs checking', 'Show network activity.'], ['weather', 'Setup needed', 'Weather needs a valid API key and location.'],
      ['yandexWeather', 'Service dependent', 'Fetch weather from Yandex.'], ['currency', 'Service dependent', 'Show a currency conversion.'],
      ['upnext', 'Calendar access', 'Show upcoming calendar events.'], ['music', 'Automation access', 'Show current media details.'],
      ['darkMode', 'Automation access', 'Toggle macOS appearance.'], ['nightShift', 'macOS dependent', 'Toggle Night Shift.'],
      ['dnd', 'Legacy / unverified', 'Do Not Disturb uses an older notification API.'],
    ],
  },
  {
    id: 'advanced-actions', label: 'Custom & legacy', description: 'Specialized controls; review their setup before adding.',
    controls: [
      ['staticButton', 'Needs an action', 'Add a button and configure its action.'], ['appleScriptTitledButton', 'Unavailable in Studio runtime', 'AppleScript controls are filtered by the current Studio runtime.'],
      ['shellScriptTitledButton', 'Unavailable in Studio runtime', 'Shell script controls are filtered by the current Studio runtime.'],
      ['memoryButton', 'Unavailable in Studio runtime', 'Shell script controls are filtered by the current Studio runtime.'],
      ['activeAppButton', 'Unavailable in Studio runtime', 'AppleScript controls are filtered by the current Studio runtime.'],
      ['close', 'Context dependent', 'Close the current submenu.'],
      ['swipe', 'Unavailable in Studio runtime', 'Swipe controls are filtered by the current Studio runtime.'],
      ['sleep', 'Unavailable in this build', 'The bundled parser does not run the configured sleep command.'], ['displaySleep', 'Unavailable in this build', 'The bundled parser does not run the configured display sleep command.'],
    ],
  },
];

function toControl([key, status, benefit]) {
  const definition = elementTypes[key];
  return definition ? { ...definition, key, status, benefit } : null;
}

export const controlCatalog = [
  ...commonGroups.map((group) => ({ ...group, controls: group.controls.map(toControl).filter(Boolean) })),
];

export const advancedControlCatalog = advancedGroups.map((group) => ({
  ...group,
  controls: group.controls.map(toControl).filter(Boolean),
}));

const controlInfo = [...controlCatalog, ...advancedControlCatalog]
  .flatMap((group) => group.controls)
  .reduce((lookup, control) => ({ ...lookup, [control.key]: control }), {});

export function getControlInfo(keyOrType) {
  if (controlInfo[keyOrType]) return controlInfo[keyOrType];
  return Object.values(controlInfo).find((control) => control.type === keyOrType) || null;
}
