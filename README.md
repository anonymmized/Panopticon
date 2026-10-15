# Panopticon

[English](README.md) · [Русский](README.ru.md)

A free, customizable app panel for macOS 13+. Built with Swift, AppKit and
SwiftUI, with no subscriptions, trials, telemetry or third-party dependencies.
Formerly called NewMacBar; the shared codebase also includes features from FreeDock.

## Features

- Place the panel on any screen edge. Adjust icon size, spacing, glass opacity,
  corners, labels, hover magnification and launch effects.
- Eight themes: Glass, Dark, Light, Aurora, Electric, Sunset, Graphite and Frost.
- Independent spaces for apps, collections, files, folders and websites.
  Switch using the panel, menu, keyboard, scrolling or search.
- Optional macOS desktop bindings and moving the panel to the cursor’s display.
  Manual switching remains available when desktop detection is unavailable.
- Pinned and running apps, active app indicators, drag-to-reorder and moving
  apps between spaces. Drop a file onto an app to open it.
- Folder stacks with a grid, search and Finder access. Website icons are
  downloaded directly from the sites you add.
- Native app menus with windows, hide, quit, pin and move actions. Window
  selection and Dock badges use optional Accessibility access.
- Up to two widgets: clock, calendar, music or focus timer. Choose compact or
  detailed presentation, color, width and background intensity.
- Spotify and Apple Music controls, artwork, seeking and volume.
- Monthly calendar and events from selected macOS calendars. Choose any local
  calendar app, Google Calendar, Outlook or another website as the click action.
- Focus sessions from 5–90 minutes, preserved across restarts.
- Profiles containing appearance and the current layout, with JSON import/export.
- Quick search for apps, spaces, shortcuts, profiles and actions, including
  abbreviations and Russian/English keyboard layout correction.
- Auto-hide, display selection and launch at login using ServiceManagement.
- Optional system Dock replacement, with original settings backed up and restored.
- English and Russian interface, with live language switching.

## Build and install

Requires macOS 13 or later and Xcode / Command Line Tools with Swift 5.9+.

```sh
xcode-select --install  # if the tools are not installed
./build.sh
open build/Panopticon.app
```

Install in Applications:

```sh
./build.sh install
open /Applications/Panopticon.app
```

Quit the previous version before installation. The installer verifies the ad-hoc
signature and keeps the previous app in a hidden backup folder. If NewMacBar is
installed in the destination, it is backed up under its old name as part of the
rename. Your preferences are preserved.

For another destination, use
`INSTALL_DIR="$HOME/Applications" ./build.sh install`.
Builds target the current Mac’s architecture (arm64 or x86_64).

Create a local disk image and checksum:

```sh
./scripts/make_dmg.sh
# build/Panopticon-<version>-<architecture>.dmg
# build/Panopticon-<version>-<architecture>.dmg.sha256
```

The DMG contains Panopticon and an Applications shortcut. These local builds use
ad-hoc signing; Developer ID signing and Apple notarization are not configured.

## Language

Use **Interface language** at the bottom of the settings sidebar:
**System**, **English** or **Русский**. Changes apply immediately to settings,
search, panel menus and widgets, without restarting or changing your layout.
System chooses the first supported language in your macOS preferences, with
English as the fallback. Calendar month and weekday names follow this choice.

Your space names, profile names, file names, app names and event titles remain
as entered. macOS-owned dialogs and errors may use the system’s language.
Privacy usage descriptions are bundled in English and Russian.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌃⌥Space | Toggle quick search; configurable in Settings |
| ⌃⌥1 … ⌃⌥9 | Select a space by its position |
| ⌃⌥← / ⌃⌥→ | Previous / next space |
| ⌃⌥D | Show / hide the panel |
| ↑ / ↓, Return, Escape | Select, open and dismiss search |
| ⌘Return in search | Pin the selected app |
| ⌘, | Open settings while the app is active |

Other apps or macOS may reserve a shortcut. Search and spaces are also available
from the menu bar and panel.

## Settings and migration

Panopticon retains the technical bundle identifier and preferences domain
`app.newmacbar.desktop` to preserve existing settings and macOS permissions.
The app, executable, Swift package and disk image are named **Panopticon**.
Do not run the old and renamed app together; they share the same identity.
Language is saved separately from spaces and appearance profiles.

Import an older `~/Library/Application Support/FreeDock/config.json` using
**Spaces → Import from FreeDock**. Import adds to your existing spaces; applying
appearance and widgets is optional. The source file is left untouched.

Choosing a calendar app controls what opens when clicked. Events are read
separately from calendar accounts connected to macOS; choosing an app does not
connect that service’s account.

Panel margins pass clicks through to other windows. macOS controls the system
Dock in Mission Control; full suppression there is not guaranteed. On normal
exit, Panopticon restores your original Dock settings. After a crash, use
**Behavior → Restore system Dock**.

## Permissions and privacy

| Permission | Purpose |
|---|---|
| Calendars | Read events after you choose to connect |
| Automation → Spotify / Music | Read and control playback after your action |
| Automation → Finder | Empty the Trash after confirmation |
| Accessibility | Optional Dock badges and app window selection |

Other features remain available without these permissions. Background polling
does not request new permissions. Network access is used for Spotify artwork and
icons from websites you add. There is no analytics. See [Privacy](docs/PRIVACY.md).

Dragging a pinned icon to the panel’s Trash removes the shortcut. Dragging a real
file from Finder moves it to the system Trash. Emptying the Trash requires confirmation.

## Development and checks

```sh
swift build -c release
.build/release/Panopticon --self-test
.build/release/Panopticon --panel-self-test
./build.sh
codesign --verify --deep --strict build/Panopticon.app
git diff --check
```

Self-tests use isolated UserDefaults and cover the model, migration, spaces,
profiles, import, geometry, calendar boundaries, search, music metadata, timer,
Dock recovery and localization. Panel tests require macOS WindowServer and check
click-through margins, first click, focus, native menus, drag-and-drop and edges.
They do not request permissions or delete real files.

GitHub Actions builds and tests the app and produces ZIP/DMG artifacts when the
owner sends changes to GitHub. Local scripts do not publish anything.

Current limits: 30 spaces, 28–60 pt icons, two widgets, up to 500 displayed items
per folder. Browser music playback is not supported. Desktop detection and
Accessibility features depend on macOS APIs and permissions.

See [contributor instructions](AGENTS.md), [integration notes](docs/INTEGRATION.md),
[localization notes](docs/LOCALIZATION.md) and [changelog](CHANGELOG.md).

## License

[MIT](LICENSE).
