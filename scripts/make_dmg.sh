#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 0 || ($# == 1 && "$1" == --skip-build) ]] || { printf 'Usage: ./scripts/make_dmg.sh [--skip-build]\n' >&2; exit 2; }
if [[ $# == 0 ]]; then ./build.sh; fi
task_app=build/NewMacBar.app
codesign --verify --deep --strict "$task_app"
task_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$task_app/Contents/Info.plist")
python3 - "$task_app" <<'VERIFY'
import hashlib, json, pathlib, plistlib, sys
app=pathlib.Path(sys.argv[1]); info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
manifest=json.loads(pathlib.Path('build/app-manifest.json').read_text())
if manifest['version'] != info['CFBundleShortVersionString'] or manifest['build'] != info['CFBundleVersion'] or manifest['binarySHA256'] != hashlib.sha256((app/'Contents/MacOS/NewMacBar').read_bytes()).hexdigest():
    raise SystemExit('App and manifest differ. Rebuild before packaging.')
VERIFY
task_signing=$(python3 -c 'import json; print(json.load(open("build/app-manifest.json"))["signing"])')
if [[ "$task_signing" == developer-id ]]; then : "${SIGN_IDENTITY:?Keep SIGN_IDENTITY set to sign the disk image too}"; fi
task_archs=$(lipo -archs "$task_app/Contents/MacOS/NewMacBar")
case "$task_archs" in
    arm64|x86_64) task_arch="$task_archs" ;;
    *arm64*x86_64*|*x86_64*arm64*) task_arch=universal ;;
    *) printf 'Unexpected binary architectures\n' >&2; exit 1 ;;
esac
task_stage=$(mktemp -d "${TMPDIR:-/private/tmp}/newmacbar-dmg.XXXXXX")
task_mounted=false
cleanup() {
    if [[ "$task_mounted" == true ]]; then hdiutil detach -quiet "$task_stage/mount" || true; fi
    rm -rf "$task_stage"
}
trap cleanup EXIT
mkdir -p "$task_stage/image" "$task_stage/mount"
ditto "$task_app" "$task_stage/image/NewMacBar.app"
ln -s /Applications "$task_stage/image/Applications"
task_output="build/NewMacBar-$task_version-$task_arch.dmg"
hdiutil create -quiet -volname "NewMacBar $task_version" -srcfolder "$task_stage/image" -ov -format UDZO "$task_output"
if [[ "$task_signing" == developer-id ]]; then codesign --force --sign "$SIGN_IDENTITY" --timestamp "$task_output"; codesign --verify --strict "$task_output"; fi
hdiutil verify "$task_output"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$task_stage/mount" "$task_output"
task_mounted=true
codesign --verify --deep --strict "$task_stage/mount/NewMacBar.app"
cmp "$task_app/Contents/MacOS/NewMacBar" "$task_stage/mount/NewMacBar.app/Contents/MacOS/NewMacBar"
[[ "$(readlink "$task_stage/mount/Applications")" == /Applications ]]
hdiutil detach -quiet "$task_stage/mount"; task_mounted=false
# An unnotarized development image is labelled in the manifest, never called a release.
python3 - "$task_output" <<'PY'
import hashlib, json, pathlib, sys
image=pathlib.Path(sys.argv[1])
manifest=json.loads(pathlib.Path('build/app-manifest.json').read_text())
manifest.update(dmg=image.name, dmgSigned=manifest["signing"] == "developer-id", dmgNotarized=False, dmgSHA256=hashlib.sha256(image.read_bytes()).hexdigest())
image.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True)+'\n')
PY
(cd build && shasum -a 256 "${task_output:t}" > "${task_output:t}.sha256")
printf 'DMG: %s/%s\n' "$PWD" "$task_output"
