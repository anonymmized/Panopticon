#!/usr/bin/env bash
# Собирает FreeDock.app. Использование:
#   ./build.sh          — собрать в build/FreeDock.app
#   ./build.sh install  — собрать и установить в /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP=FreeDock
OUT="build/$APP.app"

# Универсальная сборка (Apple Silicon + Intel) требует Xcode; с одними
# Command Line Tools собираем под текущий процессор.
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
    echo "Сборка: универсальная (arm64 + x86_64)"
else
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
    echo "Сборка: $(uname -m)"
fi

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN_DIR/$APP" "$OUT/Contents/MacOS/$APP"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
cp Resources/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$OUT"

if [[ "${1:-}" == "install" ]]; then
    pkill -x "$APP" 2>/dev/null || true
    rm -rf "/Applications/$APP.app"
    cp -R "$OUT" /Applications/
    open "/Applications/$APP.app"
    echo "Установлено: /Applications/$APP.app"
else
    echo "Готово: $OUT  (запуск: open $OUT)"
fi
