import assert from 'node:assert/strict';
import test from 'node:test';
import { controlPacks, defaultControlPackPreferences, hiddenControlPacks, normalizeControlPackPreferences, visibleControlPacks } from './controlPacks.js';

test('missing saved preferences migrate to the full legacy library', () => {
  const migrated = normalizeControlPackPreferences(null);
  assert.deepEqual(migrated.installed, controlPacks.map(({ id }) => id));
  assert.deepEqual(migrated.hidden, []);
  assert.deepEqual(migrated.favorites, []);
});

test('saved preferences discard unknown values and duplicate entries', () => {
  const value = normalizeControlPackPreferences({ installed: ['sound-media', 'sound-media', 'missing'], hidden: ['sound-media', 'missing'], favorites: ['play', 'play', 'missing'] });
  assert.deepEqual(value.installed, ['sound-media']);
  assert.deepEqual(value.hidden, ['sound-media']);
  assert.deepEqual(value.favorites, ['play']);
});

test('hidden packs remain installed and available in the extra list', () => {
  const prefs = normalizeControlPackPreferences({ ...defaultControlPackPreferences, hidden: ['sound-media'] });
  assert.ok(!visibleControlPacks(prefs).some(({ id }) => id === 'sound-media'));
  assert.ok(hiddenControlPacks(prefs).some(({ id }) => id === 'sound-media'));
  assert.ok(prefs.installed.includes('sound-media'));
});

test('an explicitly saved empty installed list remains empty', () => {
  assert.deepEqual(normalizeControlPackPreferences({ installed: [] }).installed, []);
});
