# Native Dock corrections — 0.6.1

Branch: `codex/native-dock-fixes`, based on the completed Codex branch,
with `origin/design` (`be66b3e`) merged locally. No push or main merge.
The design branch supplies specifications and tokens, not production Swift.

## Reported failure and resulting behavior

The installed 0.5.0 had an empty pinned list in its selected space. Only running
applications were visible, so terminating an app removed its temporary icon.
Replacement now imports native Dock launchers once, before hiding the system
panel. Imported apps remain pinned when closed and after relaunch. Later explicit
removals stay removed. Additional native Dock imports append missing launchers,
preserving custom items and their order. App paths on unavailable volumes survive
reloads and space changes.

`SystemDockImport` reads `persistent-apps`, handles escaped file URLs, resolves
moved apps by bundle identifier, includes Finder and deduplicates. It never writes
the system list. Native Dock visibility recovery continues to own only its three
existing autohide preferences.

The panel accepts mouse-move events and updates hover from the existing global
tracking monitor even while its empty margins pass events through. A time-based
damped spring magnifies the hovered icon and its neighbors. Animations run at up
to 120 Hz, or 30 Hz in Low Power Mode, and stop after settling. Launch bounce,
pressed feedback, entry fade/lift, window slide/fade and reduced-motion crossfade
are implemented on all four edges. Repeated model updates do not reset a window
transition. Glass has a restrained inner rim and shadow.

## Integration contracts for Claude and Gemini

- `BarModel.motionMode`: `system` (default), `full`, `reduced`, persisted in
  UserDefaults. `setMotionMode` clears the legacy reduce-motion override when
  changed in settings. System accessibility preferences are never modified.
- `ProfileAppearance.motionMode` is optional for compatibility with old archives;
  old profiles map `reduceMotion` to an appropriate mode.
- `systemDockImportVersion = 1` records the one-time migration. Keep this marker
  separate from imported appearance profiles. A new empty space is not auto-filled.
- `BarModel.importDock() -> Int` is additive and returns the number added.
  `importSystemDockIfNeeded()` runs on startup for existing replacement sessions
  and when replacement is enabled. The source closure is injectable in tests.
- The appearance page has a **Как Dock macOS** preset and an explicit motion
  mode selector, including an explanation when macOS suppresses motion.
- `--native-dock` deliberately imports missing native launchers and applies this
  preset on an ordinary launch. It does not enable Dock replacement or permissions.
- Native menus call the persistent action **Оставить в Dock**. Unpinned running
  apps continue to disappear on exit, matching macOS behavior.
- Reopening the app opens its settings even with an autohidden panel. Numeric
  editors initialize their visible text before focus and commit/clamp on Return
  or focus loss; presets and sliders keep the displayed text synchronized.

## Validation

`--self-test` covers migration from a running-only panel, closed-app persistence,
relaunch, non-destructive repeated import, intentional removals, disconnected
volumes, moved-app resolution, policy persistence and spring convergence at
30/60/120 Hz. `--panel-self-test` covers actual AppKit panel hover from click-through
state, the neighbor wave, clipping on four edges, settling/timer shutdown,
reduced motion and the existing interaction regressions. Tests use isolated
preference suites and do not close the user's applications or alter real files.
The panel tests also verify autohide completion, screen-edge reveal, visibility
while a popover is open, and model updates arriving during a reveal transition.

Verified on macOS 26.6.2 / Apple Silicon:

- Universal arm64 + x86_64 release compilation and both self-test modes pass.
  Intel execution and older macOS versions have not been exercised.
- Live installed UI shows all 11 native launchers, including closed Spotify,
  System Settings and Notion Calendar. Relaunch preserves the list and ordering;
  a second import adds no duplicates. The original macOS `persistent-apps` entries
  were compared before/after and are unchanged.
- Live numeric editor: initial `44`, input `999` clamps to `60` on Return,
  applying the native preset updates both the editor and slider to `44`.
- Full animations, `1.65` magnification, the native preset and the user's original
  auto-hide setting (`true`) are saved. Ordinary app reopening presents settings.
- Settings and panel visuals were inspected through CUA. Physical coordinate
  input to the floating panel is unavailable in this CUA surface
  (`noWindowsAvailable`); live physical hover is therefore not a visual acceptance
  claim. The real AppKit panel tests exercise that tracking/layout path directly.
- Prior app versions are retained by the installer as ZIP archives. Original
  preferences are backed up locally in
  `build/NewMacBar-settings-before-0.6.1.plist` (mode 0600, ignored by Git).

Distribution remains a local development build; the standard build/signature/DMG
verification pipeline is described in `DISTRIBUTION.md`.
