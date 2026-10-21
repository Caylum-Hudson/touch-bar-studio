# Verification — 20 October 2026

## 0.5.2 — 20 October 2026

- Scope: decluttered Studio preview and icon library, secondary options collapsed by default, separate right-edge-only Control Strip tile using the existing **Keep macOS Control Strip** setting, live Dock app/icon preview, and Dock auto-sizing that grows into available space then shrinks icons and gaps to keep all apps visible without internal scrolling. Dock and neighboring controls keep their saved positions. The Control Strip tile is not a saved profile item.
- The final installed 0.5.2 build passed `./build-local.sh` and strict code-signature verification. This includes state/catalog checks, Vite production build, Swift compilation, native AppKit Dock-fit, preview-cache, long-date and CPU fitting checks at narrowed scale, and automatic-layout constraint checks.
- All 12 frontend sizing, Dock, and viewport tests passed. The active saved profile contains Date, CPU, and Dock widgets; these sizing changes did not modify its saved widths or positions.
- DaVinci Resolve controls passed the installed 0.5.2 checks: 53 catalog entries, 48 native controls decoded, and five export-only controls filtered. All six permission-state tests passed. Browser QA confirmed the Play Reverse shortcut editor (J, keycode 38), Resolve app filter, and permission status; the temporary control was removed and the saved profile reloaded. [Resolve widget library screenshot](docs/screenshots/resolve-widget-library.png) is from the localhost editor, not the native Touch Bar. Physical Touch Bar behavior and live Resolve key delivery remain unverified.
- Installed-build browser QA confirmed the always-visible **Editing: Default bar** selector, the focused app-profile form, and immediate selection of a newly created profile for editing; the active runtime profile remains shown separately. The temporary profile was removed and the user's workspace was left unchanged. [Profile selector screenshot](docs/screenshots/profile-editing-selector.png) is an editor fixture, not a native Touch Bar capture. Final `./build-local.sh` passed.
- The active saved profile contains Date, CPU, and Dock widgets; these sizing changes did not modify its saved widths or positions.
- Frontend fit fixtures passed with 5 and 14 apps at 76-unit and 520-unit widths; every icon stayed inside its tile with no internal horizontal overflow. [Dock fit fixtures](docs/screenshots/dock-fit-fixtures.png) is an editor fixture screenshot, not a physical Touch Bar capture.
- The user confirmed dragging the right-edge Control Strip tile into place before the Dock sizing changes. They asked to reopen the latest app for visual and physical Dock-fit confirmation; that check is pending, so the new sizing is not yet user-verified in the installed app.
- Permission status for the latest build has not been checked. Physical Touch Bar actions and keyboard/media delivery remain unverified. The 0.5.1 permission result applies only to that earlier build.

## 0.5.1 — 20 October 2026

- Frontend/native build and strict code-signature verification passed. JavaScript tests passed (8/8), scoped lint reported no errors (existing hook warnings remain), and all required frontend/native checks passed.
- UI checks passed for compact and expanded previews, full-width slider precedence and Back navigation, and preservation of the enabled Touch Bar layout (Escape, Volume Slider, Brightness Slider, Dock, Exit) with Keep macOS Control Strip enabled.
- The user-authorized reauthorization flow completed for this app. Accessibility and event posting both report Granted. Physical Touch Bar actions and system Control Strip expansion/input delivery were not verified.
- Screenshots: [compact preview](docs/screenshots/control-strip-preview-collapsed.jpg) and [expanded preview](docs/screenshots/control-strip-preview-expanded.jpg).

## Post-tag 0.5.0 permission reauthorization — 20 October 2026

- The user removed the stale ad-hoc build entry, added the current 0.5.0 app, granted access, and reopened it. Accessibility and Keyboard Event Posting both reported Granted. Physical keyboard/media delivery was not tested.

## 0.5.0 — 20 October 2026

- Final frontend/native build passed, including frontend state/catalog checks, Vite production build, native arm64 build, native self-tests for focus/nested matching/blacklist/three Control Strip policy cases, and a separate expanded-slider self-test with normal AppKit access. The 41-entry native fixture audit retained 36 runtime controls and filtered five export-only script/swipe controls.
- A read-only TCC check confirmed that macOS's Device Control and Data Access row is granted for the earlier ad-hoc app hash, not the current build. The current build reports `AXIsProcessTrusted == false` and `CGPreflightPostEventAccess == false`, so keyboard/media delivery is unavailable until the user grants access to this build. No permission database or settings were changed.
- In the app UI, enabling the preference took effect immediately and survived quit/relaunch; the custom Touch Bar stayed On and the saved Dock layout remained. macOS did not prompt for access. Accessibility and event-posting checks remained false, Automation showed unknown, and Dock showed Built in.
- The same-profile focus change preserves an open submenu or expanded slider when reselecting the current effective profile, including nested app matching and blacklist transitions. A different effective profile still uses the existing Touch Bar transition. Visible focus flicker and physical Control Strip expansion were not verified.
- Physical Control Strip expansion and keyboard/media action delivery remain pending. The current authorization row applies to an earlier ad-hoc build; user reauthorization of the current build is required before action delivery can be checked. Existing Dock behavior is retained.

## 0.4.0 — 20 October 2026

- Production frontend and native builds passed. Frontend state/catalog and native expanded-layout, Back-navigation, and built-in-display-selection checks passed.
- App UI checks passed for adding volume and brightness, setting a 12-unit gap, opening and closing both expanded previews, and removing the temporary profile while restoring the original three-control Off layout.
- Position helper checks passed for local snapping and free placement. The UI was not physically dragged; saved spacing/position reload was not separately confirmed.
- Brightness round-trip passed on the active built-in display using the DisplayServices backend: display ID 1 changed from `0.5093718` to `0.5393718`, read back as `0.5393718`, then returned to `0.5093718` and was read back. The former CoreDisplay path returned a misleading `1.0` and did not write the observed value; it was replaced.
- Physical Touch Bar taps and volume hardware adjustment remain unverified. UI previews and native layout checks do not establish physical presentation or touch delivery.

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
