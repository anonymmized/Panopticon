#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
[[ $# == 0 || ($# == 1 && "$1" == install) ]] || { printf 'Usage: ./build.sh [install]\n' >&2; exit 2; }
./scripts/build_app.sh
if [[ "${1:-}" == install ]]; then ./scripts/install_app.sh; fi
