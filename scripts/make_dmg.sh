#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ "${1:-}" != --skip-build ]]; then ./build.sh; fi
codesign --verify --deep --strict build/NewMacBar.app
task_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' resources/Info.plist)
task_arch=$(uname -m)
task_stage=$(mktemp -d "${TMPDIR:-/private/tmp}/newmacbar-dmg.XXXXXX")
# Only the directory created above is removed on exit.
trap 'rm -rf "$task_stage"' EXIT
mkdir -p "$task_stage/image"
ditto build/NewMacBar.app "$task_stage/image/NewMacBar.app"
ln -s /Applications "$task_stage/image/Applications"
task_output="build/NewMacBar-$task_version-$task_arch.dmg"
hdiutil create -quiet -volname "NewMacBar $task_version" -srcfolder "$task_stage/image" -ov -format UDZO "$task_output"
hdiutil verify "$task_output"
shasum -a 256 "$task_output" > "$task_output.sha256"
printf 'DMG: %s/%s\n' "$PWD" "$task_output"
