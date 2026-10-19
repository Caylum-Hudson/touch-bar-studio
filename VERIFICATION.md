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

Version 0.1.1 permission fix: production/native build and state/native tests pass, including denied/granted permission gate tests using injected checks (no input events sent). Two native launches show the quiet notice with no automatic permission dialog. The explicit settings button opens Device Control and Data Access. The existing OS entry is On while the current process remains untrusted; no grants or permission records were changed by the agent.

Version 0.2.0: production/native build passed with coordinate decode, width/clamping, overlap, JSON position round-trip and existing state/permission tests. In the running v0.2.0 UI the precise ruler, X input and width control are visible, and live drag changes update the JSON positions. Physical coordinate placement and submenu Back reserve still require device confirmation.

## 0.3.0 control audit — 20 October 2026

- Production frontend/native build passed. The inherited Vite bundle-size warning remains.
- `local-build/check-controls.mjs`: all 41 catalog keys have unique entries, capability descriptions, matching macOS-symbol PNG assets, serializable defaults, and Date alias defaults.
- Native generated fixtures: 36 retained controls decode without unknown fallbacks; five script/swipe controls are filtered. This is decoder coverage, not 36 end-to-end successes.
- Native optional `--control-self-test local-build/control-fixtures.generated.json --include-widgets` passed: clock, battery, CPU, focus timer and volume slider initialize; no physical tap or setting-changing action was sent. AppKit checks need normal desktop process access; the tool shell sandbox could not register an AppKit process.
- Existing nested-editing, profiles, undo/redo reducer, JSON round-trip, permission-gate and coordinate tests passed. Targeted lint passed for redesigned palette, preview, icon and catalog JavaScript. Whole-repository lint was not claimed.
- UI: searched Date, added it, confirmed `MMM d`, removed the test entry and saved the original seven-item layout with Touch Bar Off. Cmd-Z in that test undid search text rather than the added item; native/menu focus routing still needs improvement.
- Physical taps, keyboard/media delivery with permission granted, display/keyboard illumination response, actual slider writes, external services, Automation and private-system toggles remain unverified. Sleep and Display Sleep are unavailable; scripts/swipe remain export-only and cannot be newly added through the palette.
- Saved before/after and unavailable-control screenshots: `docs/control-audit/`.
