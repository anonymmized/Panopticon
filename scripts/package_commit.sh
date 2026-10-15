#!/bin/zsh
# Build a selected local commit without untracked files or the working tree.
# No push, hosting or upload. NOTARIZE=1 explicitly opts in to Apple's service.
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 2 ]] || { printf 'Usage: SIGN_IDENTITY="Developer ID Application: …" ./scripts/package_commit.sh ref output-dir\n' >&2; exit 2; }
: "${SIGN_IDENTITY:?A Developer ID Application identity is required for a release candidate}"
[[ "$SIGN_IDENTITY" != - ]] || { printf 'Release candidates require Developer ID\n' >&2; exit 1; }
task_commit=$(git rev-parse --verify "$1^{commit}")
task_output="${2:A}"
task_stage=$(mktemp -d "${TMPDIR:-/private/tmp}/newmacbar-release.XXXXXX")
trap 'rm -rf "$task_stage"' EXIT
mkdir -p "$task_stage/src" "$task_output"
git archive "$task_commit" | tar -xf - -C "$task_stage/src"
[[ -x "$task_stage/src/scripts/notarize.sh" ]] || { printf 'The selected commit predates the release pipeline\n' >&2; exit 1; }
(
    cd "$task_stage/src"
    SOURCE_COMMIT="$task_commit" SOURCE_DIRTY=false ./build.sh
    ./build/Panopticon.app/Contents/MacOS/Panopticon --self-test
    ./build/Panopticon.app/Contents/MacOS/Panopticon --panel-self-test
    if [[ "${NOTARIZE:-0}" == 1 ]]; then ./scripts/notarize.sh build/Panopticon.app; fi
    ./scripts/make_dmg.sh --skip-build
    if [[ "${NOTARIZE:-0}" == 1 ]]; then ./scripts/notarize.sh build/*.dmg; fi
    ./scripts/verify_distribution.sh build/*.dmg
    cp build/*.dmg build/*.sha256 build/*.manifest.json "$task_output/"
)
printf 'Packaged local commit: %s\nArtifacts: %s\n' "$task_commit" "$task_output"
