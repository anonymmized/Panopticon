#!/bin/zsh
# Local source acceptance; no install, publication, real permissions or Dock edits.
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 0 ]] || { printf 'Usage: ./scripts/check_release.sh\n' >&2; exit 2; }
python3 scripts/check_localizations.py
python3 scripts/check_documentation.py
git diff --check
swift build -c release
.build/release/Panopticon --self-test
.build/release/Panopticon --panel-self-test
printf 'PASS: local source acceptance. Packaging and user-driven integrations are separate.\n'
