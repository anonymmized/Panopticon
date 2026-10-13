#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/NewMacBar.app/Contents/MacOS build/NewMacBar.app/Contents/Resources build/module-cache
swiftc -target arm64-apple-macos13.0 -O -module-cache-path build/module-cache Sources/NewMacBar/*.swift -o build/NewMacBar.app/Contents/MacOS/NewMacBar -framework AppKit -framework SwiftUI -framework ServiceManagement -framework EventKit -framework Carbon
cp resources/Info.plist build/NewMacBar.app/Contents/Info.plist
if [[ -f resources/AppIcon.icns ]]; then cp resources/AppIcon.icns build/NewMacBar.app/Contents/Resources/; fi
codesign --force --sign - build/NewMacBar.app
printf 'Built: %s/build/NewMacBar.app\n' "$PWD"
