# Validation status

[English](VALIDATION.md) | [Russian](VALIDATION.ru.md)

Automated checks run on a Mac with an active WindowServer. They use isolated
preferences and generated fixtures rather than real calendar, music or file permissions.

## Covered behavior

- Matching translation catalogs, interpolation, plural forms, fallback and persistence.
- Model self-tests in English and Russian.
- Settings headings updating across a language change without cached labels.
- Isolated content rendering in both languages and appearances.
- Pin import, closed-app persistence, missing volumes and additive imports.
- Space switching, profile round trips, normalization and scoped mutations.
- Hidden startup, edge dwell, click suppression, wake and overview transitions.
- Native hover tracking, neighbor magnification, reduced motion and timer teardown.
- Four-edge geometry, overflow access, transparent margins, first click and focus.
- App, folder, website and cross-space drag operations without deleting originals.
- Bounded asynchronous folders, refresh, empty states and obsolete request rejection.
- Calendar boundaries and metadata parsing without requesting live permissions.
- Dock backup validation, rollback, crash recovery and single-session ownership.
- A paused focus session surviving a planned-duration change.

## Packaging checks

Release build, native bundle tests, strict code signature verification, temporary
installer rollback and disk-image manifest verification are the local acceptance
checks. The manifests identify the actual architecture, source commit and signing
status; use them when sharing a build.

## Practical limits

Short automated tests do not establish a multi-day soak result or guarantee the
absence of all bugs. Physical Intel hardware, every display arrangement, physical sleep and
unplug cycles, full VoiceOver review and permission-dependent integrations require
separate hardware and user-driven verification.

Ad-hoc signing does not mean Apple notarization. Mission Control remains controlled
by macOS and can show its own Dock; Panopticon avoids overlapping that system surface.

## Installed-app review

The installed app was reviewed with native computer-use controls: all eleven settings
sections, English-to-System language switching, sidebar search, light appearance and
restoration of the previous appearance. The real sidebar renders correctly; the blank
sidebar in offscreen render fixtures is a snapshot limitation.

An existing configuration retained all ten pinned apps and its space, profiles,
collections and shortcuts after installation. Settings navigation and unrelated clicks
left the auto-hidden panel hidden. A real Mission Control entry and exit confirmed the
current handoff and quiet return.

Replacing the system Dock inside Mission Control is an open requirement. The current
build hides Panopticon there to prevent overlap. AppKit's
[`presentationOptions`](https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.property)
apply while the owning app is active; they do not provide a global replacement for
the Dock during overview. The build does not claim to meet that requirement.

Login-item registration, live calendar/player permissions and physical pointer-edge
gestures were not exercised against the user's configuration. Hover and drag behavior
were checked through the AppKit panel tests.

## Candidate acceptance on 2026-10-15

On macOS 26.6.2, the universal app passed both model and AppKit panel tests as arm64
and as x86_64 through Rosetta. Rosetta coverage does not establish testing on a physical
Intel Mac. The settings geometry regression checks compact and regular windows in both
languages and appearances, including long settings content.

Native computer-use review confirmed compact-window headings, sidebar scrolling,
language controls, light appearance, translated selected picker titles, localized
numeric fields, theme labels, app search and Escape dismissal. No permission-dependent
integration was connected during that review.

The installer checks complete bundle resources and preserves the original even when
both the final install move and its rollback fail. The tested failures use disposable
folders. English and Russian README images were rendered from app components and
visually reviewed; primary Markdown and all local image links passed validation.

The candidate keeps the existing preference identity. In-place installation was
checked against a private local settings backup. Pins, spaces, profiles, collections,
shortcuts and the selected space remained unchanged.

## Performance evidence

The isolated drawing benchmark uses four installed apps, two widgets and all four
edges, with 1,120 warmed layout samples and 112 drawing samples. Raw timing and process
reports are generated locally in `build`; they do not contain personal document or
event data. Short idle measurements vary with system activity and are not a battery-life
or long-term performance guarantee. Hidden-panel code defers unused pointer/button
queries; it keeps current screen geometry and the tested edge-reveal policy.

The final local synthetic run recorded layout P95 **0.079 ms** and drawing P95
**2.45 ms**. A separate 30-second auto-hide run with four apps, clock seconds and an
idle focus widget recorded **1.05% of one CPU core**, **15.3 MiB physical footprint**
and **74.3 MiB maximum resident size**. Integrations were disabled. These are scenario
measurements, not a promise for other Macs or configurations.

The isolated English lifecycle probe also passed owner restoration acknowledgement,
second-instance activation and clean removal of its session marker. Opening settings
in that probe makes its CPU result unsuitable for an idle comparison.
