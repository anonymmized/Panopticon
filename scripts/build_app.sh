#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
task_cache_id=$(printf '%s' "$PWD" | shasum -a 256 | cut -c1-12)
task_module_cache="build/module-cache-$task_cache_id"
mkdir -p build "$task_module_cache"
task_stage_dir=$(mktemp -d build/.staging.XXXXXX)
task_app="$task_stage_dir/NewMacBar.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" -O -module-cache-path "$task_module_cache" Sources/NewMacBar/*.swift -o "$task_app/Contents/MacOS/NewMacBar" -framework AppKit -framework SwiftUI -framework ServiceManagement -framework EventKit -framework Carbon
cp resources/Info.plist "$task_app/Contents/Info.plist"
if [[ -f resources/AppIcon.icns ]]; then cp resources/AppIcon.icns "$task_app/Contents/Resources/"; fi
codesign --force --sign - "$task_app"
codesign --verify --deep --strict "$task_app"
# Keep the previous bundle intact: a running process may still map its binary.
if [[ -d build/NewMacBar.app ]]; then
    task_previous_dir=$(mktemp -d build/.previous.XXXXXX)
    mv build/NewMacBar.app "$task_previous_dir/NewMacBar.app"
fi
mv "$task_app" build/NewMacBar.app
printf 'Built: %s/build/NewMacBar.app\n' "$PWD"
