const ACCESSIBILITY_CONTROLS = new Set([
  'volumeUp', 'volumeDown', 'mute', 'previous', 'play', 'next',
  'brightnessUp', 'brightnessDown', 'illuminationUp', 'illuminationDown',
  'escape', 'delete',
  'resolvePlayReverse', 'resolveStop', 'resolvePlayForward', 'resolveFrameBack',
  'resolveFrameForward', 'resolvePreviousEdit', 'resolveNextEdit', 'resolveTimelineStart',
  'resolveTimelineEnd', 'resolveMarkIn', 'resolveMarkOut', 'resolveToggleSnapping',
]);


/** Return a live permission label without implying that unknown access is denied. */
export function getControlStatus(control, accessibilityAccess = null) {
  if (control.status.startsWith('Unavailable') || control.status === 'Built in') return control.status;

  const requirements = [];
  if (ACCESSIBILITY_CONTROLS.has(control.key) || control.status.includes('Accessibility required')) {
    requirements.push(accessibilityAccess === true
      ? 'Accessibility granted'
      : accessibilityAccess === false
        ? 'Accessibility not granted'
        : 'Accessibility status unknown');
  }

  if (/Automation|Calendar access/.test(control.status)) {
    requirements.push('Automation status unknown');
  }

  if (control.status.includes('Hardware')) requirements.push('Hardware dependent');
  if (control.status === 'Setup needed' || control.status === 'Needs checking' || control.status === 'Needs an action') {
    requirements.push(control.status);
  }

  return requirements.length ? requirements.join(' · ') : control.status;
}

export function getPermissionLabel(value) {
  if (value === true) return 'Granted';
  if (value === false) return 'Not granted';
  return 'Not checked';
}

