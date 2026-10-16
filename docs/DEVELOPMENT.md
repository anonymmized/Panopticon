# Development

[English](DEVELOPMENT.md) | [Russian](DEVELOPMENT.ru.md)

The app uses Swift 5 language mode, targets macOS 13+ and has no external libraries.
AppKit owns the panel; SwiftUI owns settings, editors and popovers. Read
[Architecture](ARCHITECTURE.md) and [contributor instructions](../AGENTS.md) first.

Start tasks from current `main` in separate branches. Agree on shared model fields,
settings formats and runtime entry points before parallel edits. Use native menus,
semantic visual tokens and the shared localization service.

## Required local checks

```sh
python3 scripts/check_localizations.py
python3 scripts/check_documentation.py
swift build -c release
.build/release/Panopticon --self-test
.build/release/Panopticon --panel-self-test
./build.sh
build/Panopticon.app/Contents/MacOS/Panopticon --self-test
build/Panopticon.app/Contents/MacOS/Panopticon --panel-self-test
codesign --verify --deep --strict build/Panopticon.app
git diff --check
```

Panel tests require WindowServer. Do not run AppKit tests on Linux. Tests must use
isolated UserDefaults and generated fixtures. Calendar, music and folder permissions
are checked separately only through an explicit user action.

`--ui-review` opens the real settings presentation against isolated preferences,
without starting global shortcuts, system Dock replacement or session ownership.
`--small-window` selects the minimum review size. Review both languages and appearances,
search, editors, onboarding, long labels and accessibility feedback.

`--render-review` writes isolated settings and panel fixtures to
`build/interface-review`. It checks rendered content and language changes; native
sidebar snapshots can be incomplete, so this does not replace a live window review.

## Distribution and recovery checks

```sh
./scripts/test_install.sh
./scripts/make_dmg.sh --skip-build
./scripts/verify_distribution.sh build/Panopticon-*-arm64.dmg
```

The install test uses temporary directories and a simulated move failure to verify
rollback. The package verifier checks manifests, signatures, architectures, hashes
and the mounted image. See [Distribution](DISTRIBUTION.md) for universal builds.

## Useful local commands

| Flag | Behavior |
|---|---|
| `--settings` | Open settings on launch |
| `--diagnostics` | Read a local report without activation or permissions |
| `--visibility-state` | Query the running app's panel state without revealing it |
| `--restore-system-dock` | Coordinate restoration with the active owner |
| `--ui-benchmark` | Isolated layout/drawing benchmark |

Never commit build products, caches, installers, signing credentials or personal
profile exports. Do not push, publish or upload for notarization without an explicit
owner instruction. Local packaging performs no publication.

## Documentation images

Run `.build/release/Panopticon --render-docs` on macOS to regenerate the eight English
and Russian images in `docs/assets`. It renders real panel and settings components
with disposable demonstration preferences. Review every image before committing;
no personal events, file names, accounts or externally downloaded assets belong there.
GitHub README typography uses native Markdown; the hero image carries the custom
wordmark, system-font typography and gradient treatment.

## Local performance and lifecycle probes

`./scripts/run_platform_probe.sh 30 build/idle.json` measures a visible panel with
widgets and integrations disabled. Set `PROBE_SCENARIO=autohide` for clock-seconds and
idle-focus widgets with auto-hide. `SMOKE_LIFECYCLE=1 PROBE_LANGUAGE=en` additionally
checks owner acknowledgement and second-instance activation in English; that mode
opens settings and must not be interpreted as an idle measurement. Every probe uses
an isolated bundle identity and preferences, disables Dock replacement and connections,
and removes its generated state on exit. Reports identify the source build.

## Installer artwork

The packaged DMG uses `resources/dmg/background.png` and a checked-in Finder layout
asset, with large app and Applications icons. The layout is a source design resource,
not a built installer. Regenerate the background with `swift scripts/render_dmg_background.swift`.
The normal build uses only the saved assets and has no third-party packaging dependency.
Verify the image and visually review a freshly mounted copy after editing its layout.
The volume name remains Panopticon so the background reference resolves consistently.

`ARCH=universal ./scripts/package_commit.sh HEAD build/release` packages a selected
local commit in a temporary checkout, records that commit and performs no upload.
Ad-hoc signing is the default; `NOTARIZE=1` requires an explicitly configured Developer ID.
