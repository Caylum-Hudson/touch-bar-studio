# Changelog

## 0.3.0 — Control library audit and redesign

- Reorganise 41 addable controls around everyday sound, display, status and navigation tasks, with full labels and capability guidance.
- Add consistent macOS symbol icons to the palette and preview, and native symbols for common buttons, CPU and focus timer.
- Separate service-dependent and legacy controls; explain unavailable script/swipe and Sleep controls without claiming they work.
- Replace fabricated preview readings with illustrative labels and an explicit editor-preview caption.
- Add keyboard-accessible Add buttons, preserve Date defaults on drag, and label icon-only preview controls for accessibility.
- Decode malformed native JSON without crashing and preserve explicitly configured images/alignment over defaults.
- Add catalog coverage and native fixture checks, plus optional read-only widget initialization checks.

## 0.2.0 — 20 October 2026

- Added precise Touch Bar placement: a 1085-unit ruler, free horizontal dragging, numeric X position, width control and overlap warnings.
- Added native coordinate decoding and placement so saved positions affect the runtime, including submenu layouts with space reserved for Back.
- Kept automatic alignment available for existing MTMR layouts. Precise fields survive import/export; older MTMR runtimes may ignore the Touch Bar Studio extension.
- Modernised editor menus, palette tiles, preview controls, property fields and JSON surfaces with darker panels, lighter borders and accent highlights.
- Added frontend/native tests for coordinates, widths, bounds and JSON round trips.


## 0.1.1 — 20 October 2026

- Removed the unconditional macOS permission prompt at every launch.
- Added a silent permission status and an explicit Open permission settings button/menu command.
- Keyboard and media-key events are blocked when this build is not trusted, preventing event attempts from triggering more permission requests.
- Added an optional `STUDIO_SIGNING_IDENTITY` for builds using an existing reusable signing certificate. Ad-hoc builds can still require a fresh manual grant after an update.


## 0.1.0 — 20 October 2026

Initial Touch Bar Studio prerelease, based on MTMR Designer and the bundled MTMR runtime.

### Included

- Immediate custom Touch Bar on/off control in the app and menu bar, remembered across restart.
- Default and complete app-specific layout profiles.
- Recursive submenu editing and runtime Back navigation.
- Existing palette, property editor, presets, JSON import/export and undo/redo.
- Launcher tiles, appearance options and a folder-based photo browser.
- Finder Open With support and a macOS Service declaration.
- Source build scripts, state/native checks, setup instructions, versioning policy and illustrated usage documentation.

### Checked

Local production/native build, native decoding and profile fallback checks, recursive editor state checks, on/off UI/menu synchronization, Off persistence after restart, saving while Off, and basic photo browsing/filtering/inspection.

### Known limitations

Physical Touch Bar display, touch navigation, app-switch presentation and global shortcut delivery still need hands-on confirmation. Finder Service availability depends on macOS registration. A dedicated Finder Quick Action extension and resize-copy tool are not included. Scripts are disabled, and the local app is ad-hoc signed rather than notarized.

GitHub release assets are source archives. No installable binary is attached to this prerelease.
