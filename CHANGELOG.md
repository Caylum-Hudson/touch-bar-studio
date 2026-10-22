# Changelog

## 0.8.1 — Workspace safety and runtime cleanup (installed build verified)

- Report unreadable workspace files in Studio, require an explicit import or replacement decision, preserve the original bytes and prior valid backup, and enforce the guard in the native save API. Reject duplicate enabled app-profile bundle IDs.
- Remove stale packaged web assets through verified temporary staging and rollback-safe replacement. Clean up audio listeners, battery run-loop context, timers, background scheduler observers, and the owned network monitor when widgets are dismissed.
- Fix malformed Auto-load preference fallback and keep workspace recovery status correct across periodic refreshes after import.
- Final local build, 29 frontend tests, source/catalog checks, 20-cycle native widget lifecycle test, native profile/layout/Resolve self-tests, 56-entry control audit, widget read-only checks, strict signature verification, and installed UI review passed. The installed app shows the existing six-control layout, no workspace warning, and Accessibility granted. The visible corrupt-workspace import/confirmation flow was not end-to-end tested; native temporary-directory tests cover preservation and save guards. The 0.8.1 app bundle is 5,740 KiB, compared with 23,752 KiB before stale-asset cleanup. No CPU/RSS improvement is claimed. See [review](docs/reviews/0.8.1-code-review.md) and [verification](VERIFICATION.md).

## 0.8.0 — Even placement

- Add **Auto-place evenly** beside the preview for the current profile/submenu. Keep control sizes and visual order; use equal free gaps. If content does not fit, prompt removal and preserve the current layout. Undo restores the previous arrangement.
- Read native custom-region bounds and convert conservative intrinsic widget/Dock widths into logical coordinates; reserve submenu/Resolve navigation once, with the native Control Strip kept separately at the right. Missing native size or Dock data prompts waiting rather than claiming insufficient room.
- Browser fixture verifies arrangement, exact Undo, and unchanged JSON on no-fit. Native build and final installed UI checks are recorded in [verification](VERIFICATION.md).

## 0.7.1 — CPU temperature (installed native build verified)

- Replace the unavailable motherboard-temperature palette entry with CPU Temperature, read from available AppleSMC `Tp`/`Te` float sensor keys. The item displays the hottest plausible sensor reading and labels it as a CPU sensor, not a die average. Legacy saved motherboard entries still decode as unavailable.
- Enumerate SMC key metadata once when the CPU-temperature widget is first used, keep that metadata cached across profile changes, and read values through the shared two-second sampler. No elevated helper, shell polling, or additional permission is used.
- A bounded read-only probe on MacBookPro17,1 found 36 `Tp`/`Te` float keys and finite sampled values from 35.60–59.91°C. The staged native diagnostic returned `CPU 63°C`; one-time inventory measured 13.05 ms and the cached-key sample 10.62 ms. Sensor keys are undocumented and vary across SoCs; Macs without valid keys show **CPU —**.
- Frontend checks, five sizing tests, scoped lint, Vite build, Swift compilation, installed native self-tests, and installed UI review passed. The live widget self-test read RAM 65%, GPU 18%, and CPU 63°C; a second diagnostic read CPU 74°C and measured 11.25 ms for one-time key inventory and 9.83 ms for cached-key sampling. Strict signature and 0.7.1 version checks passed. Browser QA confirmed the CPU card, absence of a new motherboard card, add/remove, and full labels at 1280×720. See [verification](VERIFICATION.md) and [release notes](docs/releases/0.7.1.md).
- Follow-up refinements keep CPU, RAM, and GPU names in accessibility labels/tooltips while showing only whole-number percentages; distinct system icons identify each metric, and CPU temperature uses a thermometer with a compact °C label. Preview sizing includes the 18px icon, 4px gap, button padding, and font allowance. Final rebuild, native widget checks, live-width checks, five sizing tests, strict signature verification, and the 0.7.1 bundle-version check pass.
- Suppress the unwanted leading × on Studio’s compact bar using a separate app-owned overlay subclass with runtime API checks and a normal-presenter fallback. Native AppKit overlays are unchanged. Build, isolation/native checks, and strict signing pass. The user physically verified cross-app switching with × hidden while collapsed, normal native × while expanded, and the custom bar returning after collapse. See [verification](VERIFICATION.md) for the default-presenter diagnosis and fallback limits.

## 0.7.0 — System metrics (source update; native staged verification pending)

- Added native RAM and system-wide GPU usage items to the Studio palette. A single background sampler reads only the requested metric and refreshes every two seconds while RAM or GPU items are in use. The unavailable board item starts no sampler.
- RAM uses non-purgeable internal + wired + compressed pages over physical memory, with used/total bytes and the exact formula in native item details. GPU reports the busiest device when multiple IOAccelerator devices are present and shows unavailable when the counter is absent.
- Added a motherboard-temperature library item with an explicit unavailable state on this build. It does not substitute CPU, GPU, PMU, or package temperatures. See [verification](VERIFICATION.md) for the bounded local sensor check and source references.
- Added worst-case preview width and native metric calculation/absent-sensor checks. Editor labels remain illustrative; physical Touch Bar pixels and interactions still require hardware verification.

## 0.6.0 — Resolve page layouts (source update; native verification pending)

- Add independent per-page layouts for Resolve profiles, with an explicit profile fallback for pages without a custom layout. A one-time setup creates an app profile from Default and seeds Edit and Color layouts without replacing existing profiles or page layouts.
- Detect the selected Resolve page from direct Accessibility controls in its standard window while Resolve is frontmost. Offer Auto detection and a manual page picker in Studio and on the Touch Bar; unresolved detection uses the profile fallback.
- Add simultaneous Command, Option, Shift, and Control modifiers to editable keyPress shortcuts. Preserve existing unmodified and legacy actions.
- Browser QA confirmed Edit and Color templates, shortcut editing, page isolation, and saved reload. Staged native compilation and self-tests passed; live Accessibility page detection and page transitions remain unverified. Physical Touch Bar actions are unverified. This source version is not a published GitHub release.

## 0.5.2 — Focused Studio workspace (prerelease)

- Give the main Touch Bar preview and icon-based control library more room; collapse secondary options by default.
- Let users place the native Control Strip as a separate, right-edge-only preview widget through the canonical **Keep macOS Control Strip** setting. It does not add a placeholder control to a saved profile.
- Show the live Dock app list and icons in the editor. Its widget grows when space is available, then shrinks icons and gaps to fit all apps without internal scrolling; other controls keep their saved positions.
- Give Date and status previews transient content-fit widths so long formatted dates and values such as the illustrative CPU `100.0%` remain visible without changing saved widths or X positions; report insufficient placement room.
- Improve drag feedback beyond the visible Touch Bar area. The user confirmed right-edge Control Strip tile placement before the Dock sizing changes.
- The final local build passed state/catalog checks, Vite production build, Swift compilation, native Dock-fit and preview-cache checks, and strict signature verification. Frontend fit fixtures pass at narrow and wide sizes; their screenshot is an editor fixture, not the physical Touch Bar. The user requested an installed-app Dock-fit check after reopening; that check and latest-build permission status are pending, and physical Touch Bar actions remain unverified. See `docs/releases/0.5.2.md` and `VERIFICATION.md`.

## 0.5.1 — Native Control Strip layout preview (prerelease)

- When **Keep macOS Control Strip** is enabled, show a compact visual preview beside the custom Touch Bar layout. Expand opens a full-width preview; Collapse returns to the same custom layout.
- The preview is visual only. It does not send actions to macOS or change saved controls, positions, or widths.
- Frontend/native build and preview checks passed. Accessibility and event posting both report Granted; physical Touch Bar actions and system Control Strip expansion/input delivery remain unverified. See `docs/releases/0.5.1.md` and `VERIFICATION.md`.

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
