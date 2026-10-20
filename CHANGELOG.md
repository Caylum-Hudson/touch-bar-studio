# Changelog

## 0.5.0 — macOS Control Strip and live permission status (prerelease)

- Add an Appearance setting to keep macOS's Control Strip available while the custom Touch Bar is active; expanded Studio sliders temporarily use the full bar and Back returns to the prior presentation.
- Report keyboard-control availability from the running app's permission check instead of presenting a fixed permission label. macOS's existing grant is for an earlier ad-hoc build; the current build needs its own user-granted access before keyboard/media actions can work.
- Avoid rebuilding the Touch Bar when the same effective visible profile is selected again, preserving an open submenu or expanded slider. Real profile changes keep their existing presentation transition.
- Keep existing Dock behavior unchanged.
- Frontend/native builds and focused profile-focus, Control Strip, slider, and fixture checks passed. The running app reports no process access because macOS's permission row is for an earlier ad-hoc build; current-build authorization, visible focus behavior, and physical Control Strip expansion remain unverified. See `docs/releases/0.5.0.md` and `VERIFICATION.md`.

## 0.4.0 — Expanded sliders and spacing (prerelease)

- Represent volume and brightness controls as compact icons on the Touch Bar; tapping opens a full-width native slider view with Back and minimum/maximum endpoints.
- Resolve brightness reads and writes against the active built-in display instead of display ID `0`.
- Replace the JSON editor panel with the control library below the Touch Bar preview, and move the library out of the left sidebar.
- Add a configurable edge-gap option, local snapping within 10 design units, free placement beyond that distance, and saved numeric item positions.
- Build, editor and native layout checks, and a reversible built-in-display brightness round-trip passed. Physical Touch Bar taps and volume adjustment remain unverified; see `docs/releases/0.4.0.md` and `VERIFICATION.md`.

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
