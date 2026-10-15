#!/bin/zsh
# Exercise the actual installer exclusively in disposable directories.
set -euo pipefail
cd "${0:A:h:h}"
task_stage=$(mktemp -d "$PWD/build/.install-test.XXXXXX")
trap 'rm -rf "$task_stage"' EXIT
mkdir -p "$task_stage/Applications" "$task_stage/bin" "$task_stage/empty-zsh"
INSTALL_DIR="$task_stage/Applications" ./scripts/install_app.sh
codesign --verify --deep --strict "$task_stage/Applications/NewMacBar.app"
task_original=$(shasum -a 256 "$task_stage/Applications/NewMacBar.app/Contents/MacOS/NewMacBar" | cut -d' ' -f1)
INSTALL_DIR="$task_stage/Applications" ./scripts/install_app.sh
task_backups=("$task_stage/Applications/".NewMacBar-backup-*.zip(N))
(( ${#task_backups} == 1 ))
unzip -tq "${task_backups[1]}" >/dev/null
cat > "$task_stage/bin/mv" <<'MOCK'
#!/bin/zsh
if [[ "$1" == */.NewMacBar-install.*/NewMacBar.app && "$2" == */Applications/NewMacBar.app ]]; then exit 23; fi
exec /bin/mv "$@"
MOCK
chmod +x "$task_stage/bin/mv"
if ZDOTDIR="$task_stage/empty-zsh" PATH="$task_stage/bin:$PATH" INSTALL_DIR="$task_stage/Applications" /bin/zsh -f ./scripts/install_app.sh; then
    printf 'FAIL: simulated install failure was accepted\n' >&2; exit 1
fi
codesign --verify --deep --strict "$task_stage/Applications/NewMacBar.app"
task_after=$(shasum -a 256 "$task_stage/Applications/NewMacBar.app/Contents/MacOS/NewMacBar" | cut -d' ' -f1)
[[ "$task_original" == "$task_after" ]]
printf 'PASS: temporary install, update backup, simulated move failure, rollback and signature\n'
