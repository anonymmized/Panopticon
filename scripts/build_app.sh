#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 0 ]] || { printf 'Usage: ARCH=arm64|x86_64|universal SIGN_IDENTITY="…" ./scripts/build_app.sh\n' >&2; exit 2; }
task_arch="${ARCH:-$(uname -m)}"
case "$task_arch" in
    arm64|x86_64) task_archs=("$task_arch") ;;
    universal) task_archs=(arm64 x86_64) ;;
    *) printf 'Unsupported ARCH: %s\n' "$task_arch" >&2; exit 2 ;;
esac
mkdir -p build
task_stage=$(mktemp -d build/.staging.XXXXXX)
trap 'rm -rf "$task_stage"' EXIT
task_app="$task_stage/NewMacBar.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
task_binaries=()
for task_target in "${task_archs[@]}"; do
    task_swift_args=(--scratch-path ".build/$task_target" --triple "$task_target-apple-macosx13.0" -c release --product NewMacBar)
    swift build "${task_swift_args[@]}"
    task_bin_dir=$(swift build "${task_swift_args[@]}" --show-bin-path)
    task_binaries+=("$task_bin_dir/NewMacBar")
done
if (( ${#task_binaries} == 1 )); then
    cp "${task_binaries[1]}" "$task_app/Contents/MacOS/NewMacBar"
else
    lipo -create "${task_binaries[@]}" -output "$task_app/Contents/MacOS/NewMacBar"
fi
cp resources/Info.plist "$task_app/Contents/Info.plist"
cp resources/AppIcon.icns "$task_app/Contents/resources/"
plutil -lint "$task_app/Contents/Info.plist" resources/NewMacBar.entitlements
# The bundle's plist is the single version source for app, installer and manifest.
task_identity="${SIGN_IDENTITY:--}"
task_signing=adhoc
if [[ "$task_identity" == - ]]; then
    codesign --force --sign - --options runtime --timestamp=none --entitlements resources/NewMacBar.entitlements "$task_app"
else
    codesign --force --sign "$task_identity" --options runtime --timestamp --entitlements resources/NewMacBar.entitlements "$task_app"
    task_details=$(codesign --display --verbose=4 "$task_app" 2>&1)
    [[ "$task_details" == *'Authority=Developer ID Application:'* ]] || { printf 'Distribution requires a Developer ID Application certificate.\n' >&2; exit 1; }
    task_signing=developer-id
fi
codesign --verify --deep --strict "$task_app"
task_commit="${SOURCE_COMMIT:-$(git rev-parse HEAD 2>/dev/null || printf unknown)}"
task_dirty="${SOURCE_DIRTY:-$(if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then printf true; else printf false; fi)}"
python3 - "$task_app" "$task_arch" "$task_signing" "$task_commit" "$task_dirty" <<'PY'
import hashlib, json, pathlib, plistlib, sys
app, arch, signing, commit, dirty = pathlib.Path(sys.argv[1]), *sys.argv[2:]
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
manifest = dict(version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'], architecture=arch,
                minimumOS=info['LSMinimumSystemVersion'], signing=signing, notarized=False, commit=commit,
                dirty=dirty == 'true', binarySHA256=hashlib.sha256((app/'Contents/MacOS/NewMacBar').read_bytes()).hexdigest())
pathlib.Path('build/app-manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True)+'\n')
PY
# Preserve the executable mapped by any running version. Never overwrite it in place.
if [[ -d build/NewMacBar.app ]]; then
    task_previous=$(mktemp -d build/.previous.XXXXXX)
    mv build/NewMacBar.app "$task_previous/NewMacBar.app"
fi
mv "$task_app" build/NewMacBar.app
printf 'Built: %s/build/NewMacBar.app (%s, %s)\n' "$PWD" "$task_arch" "$task_signing"
