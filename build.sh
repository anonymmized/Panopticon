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
    task_install_stage=$(mktemp -d "$task_destination/.NewMacBar-install.XXXXXX")
    ditto build/NewMacBar.app "$task_install_stage/NewMacBar.app"
    codesign --verify --deep --strict "$task_install_stage/NewMacBar.app"
    if [[ -e "$task_destination/NewMacBar.app" ]]; then
        task_backup=$(mktemp -d "$task_destination/.NewMacBar-backup.XXXXXX")
        mv "$task_destination/NewMacBar.app" "$task_backup/"
    fi
    mv "$task_install_stage/NewMacBar.app" "$task_destination/NewMacBar.app"
    rmdir "$task_install_stage"
    printf 'Installed: %s/NewMacBar.app\n' "$task_destination"
fi
