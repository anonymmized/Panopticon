#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ $# -gt 1 || ($# -eq 1 && "$1" != install) ]]; then
    printf 'Usage: ./build.sh [install]\n' >&2
    exit 2
fi
./scripts/build_app.sh
if [[ "${1:-}" == install ]]; then
    task_destination="${INSTALL_DIR:-/Applications}"
    mkdir -p "$task_destination"
    # A second filename must not leave the old app running against shared settings.
    for task_existing_name in Panopticon NewMacBar; do
        task_existing_binary="$task_destination/$task_existing_name.app/Contents/MacOS/$task_existing_name"
        if [[ -f "$task_existing_binary" ]] && /usr/sbin/lsof -t "$task_existing_binary" >/dev/null 2>&1; then
            printf 'Quit %s before installing Panopticon.\n' "$task_existing_name" >&2
            exit 1
        fi
    done
    task_install_stage=$(mktemp -d "$task_destination/.Panopticon-install.XXXXXX")
    ditto build/Panopticon.app "$task_install_stage/Panopticon.app"
    codesign --verify --deep --strict "$task_install_stage/Panopticon.app"
    # Back up both names during the transition, preserving the old bundle intact.
    for task_existing_name in Panopticon NewMacBar; do
        if [[ -e "$task_destination/$task_existing_name.app" ]]; then
            task_backup=$(mktemp -d "$task_destination/.Panopticon-backup.XXXXXX")
            mv "$task_destination/$task_existing_name.app" "$task_backup/"
        fi
    done
    mv "$task_install_stage/Panopticon.app" "$task_destination/Panopticon.app"
    rmdir "$task_install_stage"
    printf 'Installed: %s/Panopticon.app\n' "$task_destination"
fi
