# Panopticon contributor instructions

[English](AGENTS.md) | [Russian](AGENTS.ru.md)

The single application is in `Sources/Panopticon`. Use Swift 5 language mode,
macOS 13+, AppKit for the panel and SwiftUI for settings and popovers. No external
libraries or telemetry. See [Architecture](docs/ARCHITECTURE.md).

## Branches and shared files

- Start tasks from current `main` in separate branches.
- Agree on shared changes to Model.swift, main.swift and settings formats before
  parallel work. Keep a concrete contract for model and service boundaries.
- Do not push, open a remote PR, publish or merge remotely without owner instruction.
- Never commit build products, caches, installers or signing credentials.

## Checks

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

Panel tests need macOS WindowServer. Do not run AppKit tests on Linux. Real folder,
music and calendar permission checks are separate and require user action. Package
locally with `./scripts/make_dmg.sh`; this does not authorize upload or publication.

## Invariants

- `BarModel` owns state. Change related fields inside `batch`.
- `BarSpace` owns apps, shortcuts and collections; profiles own appearance and a panel
  snapshot. Calendar connections are global across spaces.
- Snapshot the previous space before switching. Keep a valid selected ID after
  deletion and reordering.
- Decode new Codable fields with a default or make them optional. Normalize new
  UserDefaults settings and preserve existing data and stable application identity.
- The panel never takes keyboard focus. Transparent margins pass clicks through
  using `ignoresMouseEvents`, including after edge changes and magnification.
- Build native NSMenu context menus at click time.
- Change the system Dock only when the user enables replacement. Save and restore
  the exact original settings; retain the recovery copy after failure.
- Never request permissions during startup or background polling.
- Tear down timers and observers; owner-capturing closures use weak references.
- Tests use isolated preference suites and generated fixtures. Never empty the real
  Trash, alter user documents or connect real permissions in automated tests.
- Pair documentation in English and Russian. English Markdown contains no Cyrillic.
  Describe the current product; keep implementation history in Git.
