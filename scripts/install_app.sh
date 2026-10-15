#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 0 ]] || { printf 'Usage: INSTALL_DIR=/Applications ./scripts/install_app.sh\n' >&2; exit 2; }
task_source="$PWD/build/Panopticon.app"
task_destination="${INSTALL_DIR:-/Applications}"
[[ -d "$task_source" ]] || { printf 'Build the app first with ./build.sh\n' >&2; exit 1; }
codesign --verify --deep --strict "$task_source"
mkdir -p "$task_destination"
task_destination="${task_destination:A}"
[[ "$task_destination/Panopticon.app" != "$task_source" ]] || { printf 'Source and destination must differ\n' >&2; exit 2; }
for task_name in Panopticon NewMacBar; do
    task_binary="$task_destination/$task_name.app/Contents/MacOS/$task_name"
    if [[ -f "$task_binary" ]] && /usr/sbin/lsof -t "$task_binary" >/dev/null 2>&1; then
        printf 'Quit the installed application from its menu before updating.\n' >&2; exit 1
    fi
done
task_stage=$(mktemp -d "$task_destination/.Panopticon-install.XXXXXX")
task_moved_old=false
task_moved_legacy=false
task_installed=false
cleanup() {
    if [[ "$task_installed" == false && "$task_moved_old" == true && ! -e "$task_destination/Panopticon.app" ]]; then
        mv "$task_stage/previous.app" "$task_destination/Panopticon.app"
    fi
    if [[ "$task_installed" == false && "$task_moved_legacy" == true ]]; then
        mv "$task_stage/legacy.app" "$task_destination/NewMacBar.app"
    fi
    rm -rf "$task_stage"
}
trap cleanup EXIT
ditto "$task_source" "$task_stage/Panopticon.app"
codesign --verify --deep --strict "$task_stage/Panopticon.app"
if [[ -d "$task_destination/Panopticon.app" ]]; then
    task_backup="$task_destination/.Panopticon-backup-$(date +%Y%m%d-%H%M%S)-${task_stage:t}.zip"
    ditto -c -k --keepParent "$task_destination/Panopticon.app" "$task_backup"
    unzip -tq "$task_backup" >/dev/null
    mv "$task_destination/Panopticon.app" "$task_stage/previous.app"; task_moved_old=true
fi
if [[ -d "$task_destination/NewMacBar.app" ]]; then
    task_legacy_backup="$task_destination/.Panopticon-backup-legacy-$(date +%Y%m%d-%H%M%S)-${task_stage:t}.zip"
    ditto -c -k --keepParent "$task_destination/NewMacBar.app" "$task_legacy_backup"
    unzip -tq "$task_legacy_backup" >/dev/null
    mv "$task_destination/NewMacBar.app" "$task_stage/legacy.app"; task_moved_legacy=true
fi
mv "$task_stage/Panopticon.app" "$task_destination/Panopticon.app"; task_installed=true
printf 'Installed: %s/Panopticon.app\n' "$task_destination"
if [[ "$task_moved_old" == true ]]; then printf 'Previous version: %s\n' "$task_backup"; fi
