#!/bin/zsh
# Compile the identical isolated AppKit benchmark against an earlier local commit.
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 1 ]] || { printf 'Usage: ./scripts/compare_baseline.sh baseline-commit\n' >&2; exit 2; }
task_commit=$(git rev-parse --verify "$1^{commit}")
task_stage=$(mktemp -d "$PWD/build/.baseline.XXXXXX")
trap 'rm -rf "$task_stage"' EXIT
git archive "$task_commit" | tar -xf - -C "$task_stage"
cp Sources/Panopticon/PresentationBenchmark.swift "$task_stage/Sources/Panopticon/PresentationBenchmark.swift"
python3 - "$task_stage/Sources/Panopticon/main.swift" <<'PY'
import pathlib,sys
path=pathlib.Path(sys.argv[1]); source=path.read_text()
needle='if CommandLine.arguments.contains("--self-test")'
if needle not in source: raise SystemExit('Baseline entrypoint not recognized')
path.write_text(source.replace(needle,'if CommandLine.arguments.contains("--ui-benchmark") { runPresentationBenchmark() }\nelse '+needle,1))
PY
swift build --package-path "$task_stage" --scratch-path "$task_stage/.build" -c release
"$task_stage/.build/release/Panopticon" --ui-benchmark > build/baseline-benchmark.json
cat build/baseline-benchmark.json
