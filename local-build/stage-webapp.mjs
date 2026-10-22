import { cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

function relativeFiles(root, directory = root) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const absolute = path.join(directory, entry.name);
    return entry.isDirectory()
      ? relativeFiles(root, absolute)
      : [path.relative(root, absolute)];
  }).sort();
}

export function stageWebApp(source, destination) {
  source = path.resolve(source);
  destination = path.resolve(destination);
  const relative = path.relative(source, destination);
  const inverse = path.relative(destination, source);
  if (source === destination || (!relative.startsWith('..'+path.sep) && relative !== '..') ||
      (!inverse.startsWith('..'+path.sep) && inverse !== '..')) {
    throw new Error('WebApp source and destination must be separate, non-nested directories.');
  }
  if (!lstatSync(source, { throwIfNoEntry: false })?.isDirectory() ||
      !existsSync(path.join(source, 'index.html'))) {
    throw new Error('WebApp source must be a complete build containing index.html.');
  }

  const parent = path.dirname(destination);
  mkdirSync(parent, { recursive: true });
  const temporary = mkdtempSync(path.join(parent, `.${path.basename(destination)}.stage-`));
  const backup = path.join(parent, `.${path.basename(destination)}.backup-${process.pid}-${Date.now()}`);
  let movedOld = false;
  try {
    cpSync(source, temporary, { recursive: true });
    const digest = file => createHash('sha256').update(readFileSync(file)).digest('hex');
    const expected = relativeFiles(source).map(file => [file, digest(path.join(source, file))]);
    const actual = relativeFiles(temporary).map(file => [file, digest(path.join(temporary, file))]);
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      throw new Error('Staged WebApp files do not match the current Vite build.');
    }
    if (existsSync(destination)) {
      renameSync(destination, backup);
      movedOld = true;
    }
    try {
      renameSync(temporary, destination);
    } catch (error) {
      if (movedOld) renameSync(backup, destination);
      movedOld = false;
      throw error;
    }
    if (movedOld) rmSync(backup, { recursive: true, force: true });
  } finally {
    rmSync(temporary, { recursive: true, force: true });
    if (movedOld && !existsSync(destination) && existsSync(backup)) renameSync(backup, destination);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  if (process.argv.length !== 4) throw new Error('Usage: stage-webapp.mjs <dist> <bundle-WebApp>');
  stageWebApp(process.argv[2], process.argv[3]);
}
