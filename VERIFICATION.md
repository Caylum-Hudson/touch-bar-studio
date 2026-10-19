# Verification — 20 October 2026

Source: josmanvis/mtmr-designer, upstream commit `97670cb`.

Passed:
- React production build and native arm64 command-line build on macOS 27.0.1.
- Frontend state checks: deep child add/update, move to root, cycle prevention, undo/redo, complete profile replacement and Default restoration.
- Workspace reload generates fresh editor IDs for every depth.
- Imported unknown fields, unknown item types and unknown action fields survive JSON export.
- Comment parsing and trailing commas work without corrupting comma/bracket text inside strings; missing item types report an error.
- Native self-test: exact app matching, disabled/unmatched Default fallback, recursive group decode and script exclusion.
- Packaged native UI opens from the local application bundle with no development server.
- Apply & Save reaches native success and writes the standalone workspace file.
- Restart restores Default and its submenu data.
- UI submenu entry and Back return show the correct child/root canvas.
- Native installed-app picker adds a Firefox launcher tile.
- Photo picker loads two isolated test PNGs; filename filtering leaves one match; inspector shows 60 × 60 dimensions, ratio 1.000 and modification date.
- Targeted ESLint checks have no errors (two existing-style hook-dependency warnings).

Not claimed as verified:
- Physical Touch Bar pixels, touches, brightness/media key delivery, app-switch presentation and Back navigation.
- Global hotkey delivery in this automation environment. A Carbon hotkey handler and two shortcut choices are implemented; shortcut conflicts remain possible.
- Finder Services registration in the user's contextual menu. Open With and a Service declaration/handler are implemented; dedicated Quick Action extension and resize-copy tool are not included.
- Large photo libraries, full EXIF inspector and recursive folder browsing.

The macOS 27 SDK reports deprecation warnings in inherited MTMR code. The binary has a local ad-hoc signature, not a Developer ID signature or notarization.

On/off update: rebuilt successfully; UI button toggles Off, app-menu command toggles On and synchronizes the button; Off survives app restart; Apply & Save leaves the runtime Off. Physical Touch Bar restoration still requires hands-on confirmation.

Version 0.1.0: package and lockfile metadata, native source/shipped plist and app header agree. Local release build and state/native checks passed. Screenshots show the versioned app; the versioning illustration was rendered separately for the documentation.
