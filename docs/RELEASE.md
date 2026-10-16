# Publish Panopticon 1.0

[English](RELEASE.md) | [Russian](RELEASE.ru.md)

Version **1.0.0**, build **11**. Local packaging does not publish anything.
The intended release is a universal DMG for macOS 13+, distributed without Apple
notarization. Its release notes clearly describe first-launch approval and known limits.

## Review and package

Run the local acceptance checks in [Development](DEVELOPMENT.md). Review the actual
panel, settings and installer on the Macs intended for support. Calendar, player
control and Accessibility checks require a user action; tests never grant permissions.
See [Validation](VALIDATION.md) for the actual scope of completed checks.

```sh
./scripts/check_release.sh
ARCH=universal ./build.sh
./scripts/test_install.sh
./scripts/make_dmg.sh --skip-build
./scripts/verify_distribution.sh build/Panopticon-1.0.0-universal.dmg
```

Keep these three files together:

- `build/Panopticon-1.0.0-universal.dmg`
- `build/Panopticon-1.0.0-universal.dmg.sha256`
- `build/Panopticon-1.0.0-universal.manifest.json`

The manifest records version, build, source commit, dirty state, architecture,
signature and hashes. Publish a clean reviewed commit and the matching image.
Installers and build products do not belong in Git commits.

## Merge and tag

These commands are for the owner to run after reviewing the branch. Stop on an error;
do not replace an existing release tag.

```sh
git switch main
git pull --ff-only origin main
git merge --ff-only codex/v1-window-switcher
git push origin main
git tag -a v1.0.0 -m "Panopticon 1.0.0"
git push origin v1.0.0
```

Fast-forward keeps the reviewed commit and the DMG manifest aligned. If main has
diverged, stop, reconcile and review the combined source, then rebuild and verify
the final package before tagging. Do not reuse an image from a different source tree.

## GitHub web interface

1. Open [Releases](https://github.com/anonymmized/Panopticon/releases) and choose
   **Draft a new release**.
2. Select the pushed **v1.0.0** tag. Use **Panopticon 1.0.0** as the release title.
3. Paste the contents of [the English release notes](releases/v1.0.0.md). Optionally
   append the [Russian notes](releases/v1.0.0.ru.md) under a separate language heading.
4. Drag the DMG, checksum and manifest into the release's asset upload area.
5. Select **Set as the latest release**, leave **pre-release** unchecked, review the
   assets and choose **Publish release**.

The [latest release link](https://github.com/anonymmized/Panopticon/releases/latest)
then resolves to this release. The README download button uses that link, so future
stable releases require no README version-link edit. Publishing a Git tag alone does
not upload the DMG.

If GitHub CLI is configured, the owner can alternatively run:

```sh
gh release create v1.0.0 --verify-tag --latest \
  --title "Panopticon 1.0.0" --notes-file docs/releases/v1.0.0.md \
  build/Panopticon-1.0.0-universal.dmg \
  build/Panopticon-1.0.0-universal.dmg.sha256 \
  build/Panopticon-1.0.0-universal.manifest.json
```

## Homebrew custom tap

After creating and verifying the final DMG:

```sh
python3 scripts/make_homebrew_cask.py build/Panopticon-1.0.0-universal.dmg
ruby -c build/homebrew-panopticon/Casks/panopticon.rb
```

The command only writes a local cask. After the GitHub release is published, create
an owner-controlled public repository named **homebrew-panopticon** and add the
result as **Casks/panopticon.rb**. Review the pinned download URL and SHA-256 first.
Users can then install with:

```sh
brew install --cask anonymmized/panopticon/panopticon
```

For updates, regenerate the cask from each new verified DMG, publish that release,
then update the tap. Do not overwrite an asset after publishing its checksum.
This is a custom tap, not a claim of acceptance into the official Homebrew catalog.
The cask preserves user preferences, asks the app to quit on uninstall and does not
remove quarantine or automatically approve permissions.

## Release limits

Mission Control still displays the system Dock. Window selection requires
Accessibility and lists windows, not individual browser tabs or screenshots. The app
has no automatic updater. Developer ID signing and Apple notarization can be added
later using [Distribution](DISTRIBUTION.md); they are not claimed for this package.
