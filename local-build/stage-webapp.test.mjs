import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { stageWebApp } from './stage-webapp.mjs';

const root = mkdtempSync(path.join(os.tmpdir(), 'studio-webapp-stage-'));
try {
  const source = path.join(root, 'dist');
  const destination = path.join(root, 'app', 'WebApp');
  mkdirSync(path.join(source, 'assets'), { recursive: true });
  mkdirSync(path.join(destination, 'assets'), { recursive: true });
  writeFileSync(path.join(source, 'index.html'), 'current');
  writeFileSync(path.join(source, 'assets', 'index-current.js'), 'current asset');
  writeFileSync(path.join(destination, 'assets', 'index-obsolete.js'), 'stale asset');

  const stage = spawnSync(process.execPath, [path.resolve('local-build/stage-webapp.mjs'), source, destination], { encoding: 'utf8' });
  assert.equal(stage.status, 0, stage.stderr);

  assert.equal(readFileSync(path.join(destination, 'index.html'), 'utf8'), 'current');
  assert.equal(readFileSync(path.join(destination, 'assets', 'index-current.js'), 'utf8'), 'current asset');
  assert.throws(() => readFileSync(path.join(destination, 'assets', 'index-obsolete.js')));
  writeFileSync(path.join(destination, 'preserved-after-failure.txt'), 'previous web app');
  assert.throws(() => stageWebApp(path.join(root, 'missing-dist'), destination), /complete build containing index.html/);
  assert.equal(readFileSync(path.join(destination, 'preserved-after-failure.txt'), 'utf8'), 'previous web app');
  console.log('PASS: WebApp staging replaces stale hashed assets with the current build.');
} finally {
  rmSync(root, { recursive: true, force: true });
}
