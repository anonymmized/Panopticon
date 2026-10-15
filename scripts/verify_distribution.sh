#!/bin/zsh
# Local verification only; it never clears quarantine or bypasses Gatekeeper.
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 1 ]] || { printf 'Usage: ./scripts/verify_distribution.sh image.dmg\n' >&2; exit 2; }
task_image="${1:A}"
[[ -f "$task_image" && "$task_image" == *.dmg ]] || { printf 'Expected a disk image\n' >&2; exit 2; }
task_manifest="${task_image%.dmg}.manifest.json"
python3 - "$task_image" "$task_manifest" <<'PY'
import hashlib, json, pathlib, sys
image, manifest=pathlib.Path(sys.argv[1]), json.loads(pathlib.Path(sys.argv[2]).read_text())
if manifest['dmg'] != image.name or manifest['dmgSHA256'] != hashlib.sha256(image.read_bytes()).hexdigest():
    raise SystemExit('Disk image checksum or manifest name does not match')
if manifest.get('dmgSigned'):
    import subprocess
    subprocess.run(['codesign','--verify','--strict',str(image)],check=True)
if manifest.get('dmgNotarized'):
    import subprocess
    subprocess.run(['xcrun','stapler','validate',str(image)],check=True)
    subprocess.run(['spctl','--assess','--type','open','--context','context:primary-signature','--verbose=2',str(image)],check=True)
print('Manifest and SHA-256: OK')
PY
(cd "${task_image:h}" && shasum -a 256 -c "${task_image:t}.sha256")
hdiutil verify "$task_image"
task_stage=$(mktemp -d "${TMPDIR:-/private/tmp}/newmacbar-verify.XXXXXX")
task_mounted=false
cleanup() {
    if [[ "$task_mounted" == true ]]; then hdiutil detach -quiet "$task_stage/mount" || true; fi
    rm -rf "$task_stage"
}
trap cleanup EXIT
mkdir "$task_stage/mount"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$task_stage/mount" "$task_image"; task_mounted=true
task_app="$task_stage/mount/Panopticon.app"
codesign --verify --deep --strict "$task_app"
python3 scripts/check_bundle.py "$task_app"
[[ "$(readlink "$task_stage/mount/Applications")" == /Applications ]]
python3 - "$task_app" "$task_manifest" <<'PY'
import hashlib, json, pathlib, plistlib, subprocess, sys
app, manifest=pathlib.Path(sys.argv[1]), json.loads(pathlib.Path(sys.argv[2]).read_text())
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
binary=app/'Contents/MacOS/Panopticon'
actual=set(subprocess.check_output(['lipo','-archs',str(binary)],text=True).split())
expected={'arm64','x86_64'} if manifest['architecture']=='universal' else {manifest['architecture']}
if actual!=expected or info['CFBundleShortVersionString']!=manifest['version'] or info['CFBundleVersion']!=manifest['build'] or manifest.get('channel', info.get('PanopticonBuildChannel', 'development')) != info.get('PanopticonBuildChannel', 'development') or hashlib.sha256(binary.read_bytes()).hexdigest()!=manifest['binarySHA256']:
    raise SystemExit('Application does not match distribution manifest')
if manifest['notarized']:
    subprocess.run(['xcrun','stapler','validate',str(app)],check=True)
    subprocess.run(['spctl','--assess','--type','execute','--verbose=2',str(app)],check=True)
else:
    print('Development artifact: no Apple notarization claimed')
details=subprocess.run(['codesign','--display','--verbose=4',str(app)],capture_output=True,text=True,check=True).stderr
if manifest['signing']=='developer-id' and 'Authority=Developer ID Application:' not in details:
    raise SystemExit('Expected Developer ID Application signature')
if manifest['signing']=='adhoc' and 'Signature=adhoc' not in details:
    raise SystemExit('Expected an ad-hoc development signature')
print('Bundle version, architectures, binary SHA-256 and signature: OK')
PY
hdiutil detach -quiet "$task_stage/mount"; task_mounted=false
