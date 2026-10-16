# Validation

[English](VALIDATION.md) | [Russian](VALIDATION.ru.md)

Scope: **Panopticon 1.0.0, build 11**, reviewed on **2026-10-17**, macOS **26.6.2**
on Apple Silicon. Tests use isolated preferences and generated fixtures. No public
release, Homebrew upload or Apple notarization is performed by these checks.

## Automated acceptance

- Release build and model self-tests in English and Russian.
- AppKit panel tests as arm64 and x86_64 through Rosetta; physical Intel hardware
  is not represented by Rosetta coverage.
- 727 matching catalog entries, 638 literal Swift translation keys and 14 English/Russian
  document pairs with English-only primary Markdown and valid local links.
- Native Dock import, persistent closed-app pins, offline-volume retention, profile
  round trips, spaces, bounded settings and scoped undo.
- Running and stopped app launches both dispatch the normal reopen request. Tests
  substitute the launch transport and never open the user's real apps.
- Four-edge slide intermediate frames, complete settling, hide reversal, overview
  priority and teardown of transition timers.
- Hover springs, clipping, overflow, native menus, transparent-margin passthrough,
  first click, panel focus and compact/regular settings geometry.
- Window-list placement on offset/small displays, nonactivating panels, explicit
  permission fallback, space-change dismissal and stale asynchronous query rejection.
- Bounded, cancellable folder reads; focus-session persistence and timer normalization;
  calendar boundaries, metadata parsing and drag operations using fixtures.
- Temporary installation, verified backup, failed-install rollback and preservation
  of the original when rollback itself fails.

## Visual review

Native computer-use review checked the new settings card in a compact window,
Russian and English, search using both languages and disabling/re-enabling the
feature without requesting permissions. The selected native picker labels update
with the interface language. User-supplied app/display names remain unchanged.

The ready, permission and unavailable window-list components were rendered with
fixture data; English/Russian and light/dark states were reviewed. README images use
actual app components and demonstration data, not personal window titles or calendars.

The Finder installer was reviewed after mounting a freshly generated image. The
background, app/Applications icon positions and complete footer were visible. Its
portable background reference excludes the build machine's user and source-image
paths. Packaging stores the reviewed layout as a source asset; regular builds need
no external packaging library.

## Distribution

The universal bundle contains arm64 and x86_64, both catalogs, localized permission
strings and the app icon. Strict code signature checks pass. The image verifier
mounts read-only, verifies the app, architectures, versions, binary/image hashes,
layout/artwork hashes, Applications link and volume icon. The previous DMG is replaced
only after the next image has passed its local checks.

The generated custom-tap cask is pinned to the verified image's SHA-256 and passes
Ruby syntax checking. It is not published; installing from the remote tap is a
separate check after the owner publishes both the release and the tap.

The app retains its existing preferences identity. Existing configurations load the
new window-selection flag with a default; space snapshots and appearance profiles
do not overwrite it. No release check modifies the user's current Dock settings.

## Measured performance

The local drawing scenario uses four installed apps, two widgets and four edges:
1,120 warmed layout samples and 112 drawing samples. Layout P95 was **0.081 ms**;
drawing P95 was **2.60 ms**, with median **2.08 ms**.

A separate 30-second idle run after 15 seconds of warmup, with four apps, auto-hide,
clock seconds and an idle focus widget, recorded **0.73% of one CPU core**,
**15.3 MiB physical footprint** and **74.5 MiB maximum resident size**. Connections
were disabled and settings were closed. The window-list panel is created on first
use, not while the Dock is idle. Raw reports remain local in `build`.

These are short scenario measurements, not battery-life or long-duration guarantees.
They vary with system activity and do not cover active window queries or playback.

## Separate user checks and limits

Live Accessibility window selection, calendar events, player control, login-item
registration, full VoiceOver review, physical sleep and display unplug cycles require
separate explicit user actions and hardware coverage. Automated tests do not grant
permissions or manipulate the user's real windows/documents. These results do not
claim a multi-day soak test or the absence of all bugs.

The package is ad-hoc signed and **not notarized by Apple**. First launch can require
per-app approval in Privacy & Security. **Mission Control uses the system Dock**;
Panopticon yields there to prevent overlap. A complete replacement inside overview
is not implemented. Window selection lists windows, not individual browser tabs or
screenshots, and the application has no automatic updater.
