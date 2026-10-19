# Palette control runtime audit

This audit compares the 41-entry palette/catalog and generated defaults with the bundled native decoder, `StudioStore.safeItems`, `TouchBarController`, and concrete widget implementations. The catalog check covers 41/41 entries, including the Date, Memory, and Active App aliases. Source and safe runtime initialization checks cannot establish physical Touch Bar taps or all OS-level effects.

## What is available

| Controls | Native/runtime status | Requirements and limits |
|---|---|---|
| Escape, Delete | Active keypress controls. | The key event is sent only when macOS Accessibility/keyboard access is trusted. The editor can report/open the permission setting; it cannot grant access. |
| Brightness Up/Down, Keyboard Illumination Up/Down, Volume Up/Down, Mute; Previous/Play/Next | Active HID media-key controls. | Delivery is guarded by keyboard permission. Brightness and keyboard lighting depend on compatible hardware; media keys depend on a responding media target. |
| Brightness Slider | Active slider using the display brightness API. | Hardware/API dependent; its value can initialize without proving the display changes. |
| Volume Slider | Active slider using CoreAudio output-volume APIs. | Depends on the selected audio device exposing writable main volume. Initialization is not proof that adjustment works on every route. |
| Time, Date, Battery, CPU, Pomodoro | Active local widgets. Date is an alias of `timeButton` with `MMM d`. Pomodoro defaults to 1500/300 seconds. | CPU displays local usage; tapping it runs an Activity Monitor/System Events AppleScript and can require Automation access. Time, battery, CPU, timer, and volume slider have local initialization coverage in the native control self-test. |
| Dock, Group, Close, Exit TouchBar | Active navigation/display controls. `close` leaves a submenu; `exitTouchbar` dismisses the Touch Bar. | Close has no useful effect outside a submenu. Dock behavior depends on the system/app context. |
| Input Source, Night Shift, Dark Mode, Do Not Disturb | Native widget implementations are present and controls render. | Input Source cycles through input sources. Night Shift uses a private CoreBrightness API and macOS support varies. Dark Mode invokes System Events AppleScript and ignores errors, so Automation access can affect it. DnD writes private Notification Center preferences and posts a private notification; treat it as legacy/version-fragile. |
| Music | Native widget renders current media and has single-tap play/pause, double-tap previous, long-tap next. | Uses ScriptingBridge against supported players; player availability and macOS Automation authorization can limit results. |
| Currency, Weather, Yandex Weather, Network, Up Next | Native widgets parse and render. | External services/network or system data apply. Weather has an empty API key by default. Up Next depends on calendar events/access. Network monitoring depends on a usable interface/process. Yandex and Currency service availability should be verified. |
| Static Button | Active display control. | No action until configured; safe retained actions are keypress/HID and URL. URL opens another app/browser. |
| AppleScript Button, Active App, Shell Script Button, Memory, Swipe | Intentionally unavailable in the active Studio runtime. Titled script buttons render as “Script disabled”; `safeItems` removes script buttons and swipe, and filters AppleScript/shell actions. These are catalog/import/export entries, not functioning palette controls here. | Do not suggest these controls can run scripts in this build. |
| Sleep, Display Sleep | Explicitly unavailable. Native defaults display “Sleep unavailable” / “Display sleep unavailable”. Their decoded shell actions have no controller closure, so they do not run `pmset`. | Do not test by tapping or represent them as working. |

## Checks and evidence

`local-build/check-controls.mjs` is designed to check catalog uniqueness, capability text, icon files, and serializable defaults for all palette entries, and to generate fixtures. The native `--control-self-test <fixture-path>` then decodes every fixture through `safeItems`, expects 36 retained controls and five filtered script/swipe controls, checks malformed JSON handling, and optionally initializes local clock, battery, CPU, focus timer, and volume slider widgets without sending actions when `--include-widgets` is supplied. The production build and both commands passed on this Mac. Widget checks use the extra `--include-widgets` flag and require an interactive macOS/AppKit session. The command-line sandbox could not register an AppKit process; the same checks passed with normal local process access.

These checks do not tap the Touch Bar, synthesize a key, change volume/brightness, invoke script actions, grant permissions, or verify external services, Automation prompts, calendar access, private system toggles, or hardware response. Physical/live QA remains a separate check on supported hardware. Catalog/type coverage and local view initialization are narrower claims than end-to-end control behavior.

## Follow-up fixes

Keep unavailable controls visibly marked in the palette and prevent them from being mistaken for working controls. Either implement and safely gate script/sleep actions or keep their current unavailable labels and exclude them from the primary palette. Surface permission status for keyboard and CPU/Music/Dark Mode Automation pathways. Replace or version-gate private DnD/Night Shift mechanisms, validate external service setup, and make hardware-dependent slider limitations clear. Add automated assertions that safe actions survive `safeItems`, script/swipe entries are filtered, and Sleep/Display Sleep remain unavailable until their controller behavior changes.
