import test from 'node:test';
import assert from 'node:assert/strict';
import { restoreWorkspaceProfiles, workspaceImportError } from './workspaceValidation.js';

const validWorkspace = () => ({
  version: 1,
  profiles: {
    default: { items: [{ type: 'staticButton', title: 'Default' }] },
    resolve: {
      bundleId: 'com.blackmagic-design.DaVinciResolve',
      enabled: true,
      items: [{ type: 'staticButton', title: 'Fallback' }],
      resolvePageLayouts: { edit: [{ type: 'staticButton', title: 'Edit' }] },
    },
  },
});

test('workspace import validates every profile and Resolve page before dispatch', () => {
  const workspace = validWorkspace();
  assert.equal(workspaceImportError(workspace), null);

  const brokenProfile = validWorkspace();
  brokenProfile.profiles.default.items = [{}];
  assert.match(workspaceImportError(brokenProfile), /Every control needs a type/);

  const brokenResolveLayout = validWorkspace();
  brokenResolveLayout.profiles.resolve.resolvePageLayouts.color = [{ type: 'group', items: [{}] }];
  assert.match(workspaceImportError(brokenResolveLayout), /Every control needs a type/);

  const malformedPages = validWorkspace();
  malformedPages.profiles.resolve.resolvePageLayouts = [];
  assert.match(workspaceImportError(malformedPages), /must be an object/);
});

test('enabled imported app profiles require a non-empty bundle identifier', () => {
  const missingBundle = validWorkspace();
  delete missingBundle.profiles.resolve.bundleId;
  assert.match(workspaceImportError(missingBundle), /needs a bundle identifier/);

  const disabledLegacy = validWorkspace();
  disabledLegacy.profiles.resolve.enabled = false;
  delete disabledLegacy.profiles.resolve.bundleId;
  assert.equal(workspaceImportError(disabledLegacy), null);
});

test('enabled imported app profiles cannot target the same bundle identifier', () => {
  const duplicate = validWorkspace();
  duplicate.profiles.safari = { ...duplicate.profiles.resolve, bundleId: 'com.apple.finder' };
  duplicate.profiles.resolve.bundleId = 'com.apple.finder';
  assert.match(workspaceImportError(duplicate), /cannot share bundle identifier/);
});

test('malformed restore is refused instead of yielding empty editor profiles', () => {
  const malformed = validWorkspace();
  malformed.profiles.resolve.items = [{}];
  assert.equal(restoreWorkspaceProfiles(malformed), null);
  assert.equal(restoreWorkspaceProfiles(validWorkspace()).default.items[0].type, 'staticButton');
});
