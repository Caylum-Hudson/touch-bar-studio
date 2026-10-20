import test from 'node:test';
import assert from 'node:assert/strict';
import { getControlStatus, getPermissionLabel } from './controlAvailability.js';

const escapeControl = { key: 'escape', status: 'Accessibility required', benefit: 'Send Escape.' };
const brightnessControl = { key: 'brightnessUp', status: 'Accessibility required · Hardware dependent', benefit: 'Increase brightness.' };
const automationControl = { key: 'darkMode', status: 'Automation access', benefit: 'Toggle appearance.' };
const dockControl = { key: 'dock', status: 'Built in', benefit: 'Show Dock apps.' };

test('Accessibility status follows the live permission state', () => {
  assert.equal(getControlStatus(escapeControl, true), 'Accessibility granted');
  assert.equal(getControlStatus(escapeControl, false), 'Accessibility not granted');
  assert.equal(getControlStatus(escapeControl, null), 'Accessibility status unknown');
});

test('hardware requirements remain separate from Accessibility status', () => {
  assert.equal(getControlStatus(brightnessControl, true), 'Accessibility granted · Hardware dependent');
  assert.equal(getControlStatus(brightnessControl, false), 'Accessibility not granted · Hardware dependent');
});

test('unknown Automation access is not reported as missing', () => {
  assert.equal(getControlStatus(automationControl, false), 'Automation status unknown');
});

test('built-in controls such as Dock retain their status', () => {
  assert.equal(getControlStatus(dockControl, false), 'Built in');
});

test('live permission diagnostics distinguish granted, not granted, and unchecked', () => {
  assert.equal(getPermissionLabel(true), 'Granted');
  assert.equal(getPermissionLabel(false), 'Not granted');
  assert.equal(getPermissionLabel(null), 'Not checked');
});
