# Distribution

[English](DISTRIBUTION.md) | [Russian](DISTRIBUTION.ru.md)

## Local builds

```sh
./build.sh
ARCH=x86_64 ./build.sh
ARCH=universal ./build.sh
```

`resources/Info.plist` is the version source. Each build stages the bundle, includes
English and Russian resources, signs it and verifies the signature. The previous
built bundle remains intact. `build/app-manifest.json` records version, architecture,
source commit, dirty state, binary SHA-256 and signing status.

## Install and rollback

Quit the installed app, then run `./scripts/install_app.sh` or `./build.sh install`.
The installer rejects a running destination, verifies a staged copy, keeps a ZIP
backup and restores the previous bundle if the final move fails. The same protection
applies during a filename transition. `INSTALL_DIR` can select a user-owned directory.

`./scripts/test_install.sh` exercises installation, backup and rollback in temporary
folders. It never updates the actual Applications directory.

## Disk image

```sh
ARCH=universal ./build.sh
./scripts/make_dmg.sh --skip-build
./scripts/verify_distribution.sh build/Panopticon-*-universal.dmg
```

The image contains the app and an Applications shortcut. A checksum and manifest are
written beside it. Verification mounts the image read-only, checks the bundle, hashes,
architectures and signature, then detaches it.

## Developer ID and notarization

Ad-hoc signing is for local development and does not establish Apple notarization.
For a distributable signed app, the owner must have a Developer ID certificate and
an existing notarytool Keychain profile.

```sh
export SIGN_IDENTITY='Developer ID Application: YOUR IDENTITY'
ARCH=universal ./build.sh
NOTARY_PROFILE='YOUR KEYCHAIN PROFILE' ./scripts/notarize.sh build/Panopticon.app
./scripts/make_dmg.sh --skip-build
NOTARY_PROFILE='YOUR KEYCHAIN PROFILE' ./scripts/notarize.sh build/Panopticon-*-universal.dmg
./scripts/verify_distribution.sh build/Panopticon-*-universal.dmg
```

The notarize command is an explicit upload to Apple. Other build and package commands
do not upload. Credentials belong in Keychain, never source files. Do not claim an
ad-hoc build is notarized, and do not clear quarantine attributes as a substitute.
