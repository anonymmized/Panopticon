# Panopticon 1.0 release readiness

[English](RELEASE.md) | [Russian](RELEASE.ru.md)

Version: **1.0.0**, build **10**. Channel: **release candidate**.
No public release or GitHub upload is performed by the local checks.

## Acceptance

| Area | Local acceptance |
|---|---|
| Source | Release build and isolated model/panel tests |
| Languages | Matching catalogs, placeholders, plural forms and English-only primary documentation |
| Persistence | Offline pins survive profile application and restart; spaces and profile round trips |
| Background work | Cancelled folder reads cannot publish; timer inputs and restored durations are bounded |
| Interaction | Four edges, overflow, click-through margins, native menus, hover springs and quiet reveal policy |
| Packaging | Complete resources, stable identity, universal architectures, strict signature and image hashes |
| Installer | Verified backup, failed-install rollback and preservation when rollback itself fails |
| Documentation | Real component previews with disposable data; paired English and Russian guides |

Run `./scripts/check_release.sh`, build with `ARCH=universal ./build.sh`, then run
`./scripts/test_install.sh`, package the image and verify it with
`./scripts/verify_distribution.sh`. Record actual results in [Validation](VALIDATION.md).
A command succeeding is not a substitute for the separate user-driven checks below.

## Before public distribution

- Review the candidate on the Macs and displays intended for support. Short automated
  checks do not establish a multi-day soak result.
- Check calendar access, player control, Accessibility and login-item registration
  through explicit user actions. Automated tests do not request these permissions.
- Confirm signing and notarization for the intended distribution. Ad-hoc local signing
  is not Apple notarization. A Developer ID signing identity is not configured on the
  current build machine; Apple Development is a different certificate type.
- Keep Mission Control behavior explicit in release notes: overview shows the system
  Dock and suppresses Panopticon. Full replacement in that mode remains unimplemented.
- Publish only the reviewed commit and its matching DMG, manifest and SHA-256 file,
  after a separate owner instruction. No release tag has been published by this work.

## Candidate changes

- Preserves pinned apps from temporarily disconnected volumes when applying profiles.
- Propagates cancellation to folder workers and releases the loading indicator.
- Bounds restored focus sessions and rejects non-finite duration input.
- Distinguishes a fresh focus session from a paused session in labels and actions.
- Keeps numeric controls and transient status labels in the selected interface language.
- Trims obsolete icon-cache entries when changing panel contents.
- Validates resources before installation and preserves originals after rollback failure.
- Adds illustrated, bilingual documentation with reproducible component previews.

Build and signing details: [Distribution](DISTRIBUTION.md). Daily use: [User guide](USAGE.md).
