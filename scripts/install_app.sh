#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 0 ]] || { printf 'Usage: INSTALL_DIR=/Applications ./scripts/install_app.sh\n' >&2; exit 2; }
task_source="$PWD/build/NewMacBar.app"
task_destination="${INSTALL_DIR:-/Applications}"
[[ -d "$task_source" ]] || { printf 'Build the app first with ./build.sh\n' >&2; exit 1; }
codesign --verify --deep --strict "$task_source"
mkdir -p "$task_destination"
task_destination="${task_destination:A}"
[[ "$task_destination/NewMacBar.app" != "$task_source" ]] || { printf 'Source and destination must differ\n' >&2; exit 2; }
if [[ -f "$task_destination/NewMacBar.app/Contents/MacOS/NewMacBar" ]] && /usr/sbin/lsof -t "$task_destination/NewMacBar.app/Contents/MacOS/NewMacBar" >/dev/null 2>&1; then
    printf 'Quit the installed NewMacBar before updating. Its menu has “Завершить”.\n' >&2; exit 1
fi
task_stage=$(mktemp -d "$task_destination/.NewMacBar-install.XXXXXX")
task_moved_old=false
task_installed=false
cleanup() {
    if [[ "$task_installed" == false && "$task_moved_old" == true && ! -e "$task_destination/NewMacBar.app" ]]; then
        mv "$task_stage/previous.app" "$task_destination/NewMacBar.app"
    fi
    rm -rf "$task_stage"
}
trap cleanup EXIT
ditto "$task_source" "$task_stage/NewMacBar.app"
codesign --verify --deep --strict "$task_stage/NewMacBar.app"
if [[ -d "$task_destination/NewMacBar.app" ]]; then
    task_backup="$task_destination/.NewMacBar-backup-$(date +%Y%m%d-%H%M%S)-${task_stage:t}.zip"
    ditto -c -k --keepParent "$task_destination/NewMacBar.app" "$task_backup"
    unzip -tq "$task_backup" >/dev/null
    mv "$task_destination/NewMacBar.app" "$task_stage/previous.app"; task_moved_old=true
fi
mv "$task_stage/NewMacBar.app" "$task_destination/NewMacBar.app"; task_installed=true
printf 'Installed: %s/NewMacBar.app\n' "$task_destination"
if [[ "$task_moved_old" == true ]]; then printf 'Previous version: %s\n' "$task_backup"; fi
