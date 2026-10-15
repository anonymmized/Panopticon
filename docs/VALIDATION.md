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
absence of all bugs. Intel execution, every display arrangement, physical sleep and
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
