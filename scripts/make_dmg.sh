#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 0 || ($# == 1 && "$1" == --skip-build) ]] || { printf 'Usage: ./scripts/make_dmg.sh [--skip-build]\n' >&2; exit 2; }
if [[ $# == 0 ]]; then ./build.sh; fi
task_app=build/Panopticon.app
codesign --verify --deep --strict "$task_app"
task_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$task_app/Contents/Info.plist")
python3 - "$task_app" <<'VERIFY'
import hashlib, json, pathlib, plistlib, sys
app=pathlib.Path(sys.argv[1]); info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
manifest=json.loads(pathlib.Path('build/app-manifest.json').read_text())
if manifest['version'] != info['CFBundleShortVersionString'] or manifest['build'] != info['CFBundleVersion'] or manifest.get('channel', info.get('PanopticonBuildChannel', 'development')) != info.get('PanopticonBuildChannel', 'development') or manifest['binarySHA256'] != hashlib.sha256((app/'Contents/MacOS/Panopticon').read_bytes()).hexdigest():
    raise SystemExit('App and manifest differ. Rebuild before packaging.')
VERIFY
task_signing=$(python3 -c 'import json; print(json.load(open("build/app-manifest.json"))["signing"])')
if [[ "$task_signing" == developer-id ]]; then : "${SIGN_IDENTITY:?Keep SIGN_IDENTITY set to sign the disk image too}"; fi
task_archs=$(lipo -archs "$task_app/Contents/MacOS/Panopticon")
case "$task_archs" in
    arm64|x86_64) task_arch="$task_archs" ;;
    *arm64*x86_64*|*x86_64*arm64*) task_arch=universal ;;
    *) printf 'Unexpected binary architectures\n' >&2; exit 1 ;;
esac
task_stage=$(mktemp -d "$PWD/build/.dmg.XXXXXX")
task_mounted=false
cleanup() {
    if [[ "$task_mounted" == true ]]; then hdiutil detach -quiet "$task_stage/mount" || true; fi
    rm -rf "$task_stage"
}
trap cleanup EXIT
mkdir -p "$task_stage/image" "$task_stage/mount"
mkdir -p "$task_stage/image/.background"
cp resources/dmg/background.png "$task_stage/image/.background/background.png"
cp resources/dmg/finder-layout.dat "$task_stage/image/.DS_Store"
cp resources/AppIcon.icns "$task_stage/image/.VolumeIcon.icns"
ditto "$task_app" "$task_stage/image/Panopticon.app"
ln -s /Applications "$task_stage/image/Applications"
task_output="build/Panopticon-$task_version-$task_arch.dmg"
task_verified="$task_stage/Panopticon-$task_version-$task_arch.dmg"
hdiutil create -quiet -fs HFS+ -volname Panopticon -srcfolder "$task_stage/image" -format UDRW "$task_stage/edit.dmg"
hdiutil attach -quiet -readwrite -nobrowse -noautoopen -mountpoint "$task_stage/mount" "$task_stage/edit.dmg"
task_mounted=true
# Set metadata on the generated volume, never on the user's Finder preferences.
xattr -wx com.apple.FinderInfo 0000000000000000040000000000000000000000000000000000000000000000 "$task_stage/mount"
hdiutil detach -quiet "$task_stage/mount"; task_mounted=false
hdiutil convert -quiet -format UDZO -o "$task_verified" "$task_stage/edit.dmg"
if [[ "$task_signing" == developer-id ]]; then codesign --force --sign "$SIGN_IDENTITY" --timestamp "$task_verified"; codesign --verify --strict "$task_verified"; fi
hdiutil verify "$task_verified"
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$task_stage/mount" "$task_verified"
task_mounted=true
codesign --verify --deep --strict "$task_stage/mount/Panopticon.app"
cmp "$task_app/Contents/MacOS/Panopticon" "$task_stage/mount/Panopticon.app/Contents/MacOS/Panopticon"
[[ "$(readlink "$task_stage/mount/Applications")" == /Applications ]]
cmp resources/dmg/background.png "$task_stage/mount/.background/background.png"
cmp resources/dmg/finder-layout.dat "$task_stage/mount/.DS_Store"
hdiutil detach -quiet "$task_stage/mount"; task_mounted=false
# Only replace the previous artifact once the new image has passed verification.
mv -f "$task_verified" "$task_output"
# Record signing and notarization accurately, including an ad-hoc public package.
python3 - "$task_output" <<'PY'
import hashlib, json, pathlib, sys
image=pathlib.Path(sys.argv[1])
manifest=json.loads(pathlib.Path('build/app-manifest.json').read_text())
manifest.update(dmg=image.name, dmgSigned=manifest["signing"] == "developer-id", dmgNotarized=False, dmgSHA256=hashlib.sha256(image.read_bytes()).hexdigest())
manifest['installerBackgroundSHA256']=hashlib.sha256(pathlib.Path('resources/dmg/background.png').read_bytes()).hexdigest()
manifest['installerLayoutSHA256']=hashlib.sha256(pathlib.Path('resources/dmg/finder-layout.dat').read_bytes()).hexdigest()
image.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True)+'\n')
PY
(cd build && shasum -a 256 "${task_output:t}" > "${task_output:t}.sha256")
printf 'DMG: %s/%s\n' "$PWD" "$task_output"
