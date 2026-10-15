# Panopticon

[English](README.md) | [Russian](README.ru.md)

A free, local-first app panel for macOS 13 and later. Pin apps, organize spaces,
add useful widgets and choose a look that fits your desktop. Built with Swift,
AppKit and SwiftUI, without subscriptions, telemetry or third-party libraries.

## Everyday use

- Pinned apps stay on the panel after quitting. Right-click a running app and choose
  **Keep in Dock**, or use **Add from macOS Dock** in Settings.
- Spaces hold independent apps, collections, folders and website shortcuts.
- The panel supports all four screen edges, multiple displays, auto-hide,
  hover magnification and launch feedback.
- Clock, calendar, music and focus widgets offer compact or detailed layouts.
- Choose the app or website to open from the calendar widget. Calendar events
  come separately from accounts connected to macOS.
- Search finds apps, spaces, shortcuts, profiles and actions.
- Settings and popovers support system, light and dark appearances. Choose English,
  Russian or the system language without restarting.

## Build and install

Requires macOS 13+ and Xcode or Command Line Tools with Swift 5.9+.

```sh
swift build -c release
./build.sh
open build/Panopticon.app
```

Quit the installed app before updating:

```sh
./build.sh install
open /Applications/Panopticon.app
```

The installer verifies the signature and keeps a ZIP backup before replacing an
installed app. Preferences and permissions keep their existing application identity.
For another destination, set `INSTALL_DIR="$HOME/Applications"`.

Build a universal app and a local disk image:

```sh
ARCH=universal ./build.sh
./scripts/make_dmg.sh --skip-build
./scripts/verify_distribution.sh build/Panopticon-*-universal.dmg
```

Local builds use ad-hoc signing unless you supply a Developer ID identity.
Signing and notarization instructions are in [Distribution](docs/DISTRIBUTION.md).

## Dock replacement

Enable **Replace system Dock** deliberately in Settings. Panopticon imports pinned
apps, saves the system Dock settings and restores them when you quit. You can also
choose **Restore system Dock** from the menu bar or Settings.

Auto-hide responds to a short hover at the chosen screen edge. Ordinary mouse clicks,
app activation and background updates do not reveal the panel.

Mission Control remains managed by macOS. Panopticon avoids overlapping the system
Dock there; it does not claim a complete replacement inside Mission Control.

## Documentation

- [User guide](docs/USAGE.md)
- [Privacy and permissions](docs/PRIVACY.md)
- [Architecture and service contracts](docs/ARCHITECTURE.md)
- [Development and validation](docs/DEVELOPMENT.md)
- [Localization](docs/LOCALIZATION.md)
- [Design system](design/README.md)
- [Validation status](docs/VALIDATION.md)

English files contain English only. Russian counterparts use the `.ru.md` suffix.

## Quick checks

```sh
python3 scripts/check_localizations.py
python3 scripts/check_documentation.py
swift build -c release
.build/release/Panopticon --self-test
.build/release/Panopticon --panel-self-test
./build.sh
codesign --verify --deep --strict build/Panopticon.app
git diff --check
```

Tests use isolated preferences and do not request permissions, empty the Trash or
modify real documents. Panel tests need a macOS WindowServer session.

[MIT license](LICENSE).
