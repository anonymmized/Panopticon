#!/bin/zsh
# Exercise the actual installer exclusively in disposable directories.
set -euo pipefail
cd "${0:A:h:h}"
task_stage=$(mktemp -d "$PWD/build/.install-test.XXXXXX")
trap 'rm -rf "$task_stage"' EXIT
mkdir -p "$task_stage/Applications" "$task_stage/bin" "$task_stage/empty-zsh"
INSTALL_DIR="$task_stage/Applications" ./scripts/install_app.sh
codesign --verify --deep --strict "$task_stage/Applications/Panopticon.app"
task_original=$(shasum -a 256 "$task_stage/Applications/Panopticon.app/Contents/MacOS/Panopticon" | cut -d' ' -f1)
INSTALL_DIR="$task_stage/Applications" ./scripts/install_app.sh
task_backups=("$task_stage/Applications/".Panopticon-backup-*.zip(N))
(( ${#task_backups} == 1 ))
unzip -tq "${task_backups[1]}" >/dev/null
cat > "$task_stage/bin/mv" <<'MOCK'
#!/bin/zsh
if [[ "$1" == */.Panopticon-install.*/Panopticon.app && "$2" == */Applications/Panopticon.app ]]; then exit 23; fi
exec /bin/mv "$@"
MOCK
chmod +x "$task_stage/bin/mv"
if ZDOTDIR="$task_stage/empty-zsh" PATH="$task_stage/bin:$PATH" INSTALL_DIR="$task_stage/Applications" /bin/zsh -f ./scripts/install_app.sh; then
    printf 'FAIL: simulated install failure was accepted\n' >&2; exit 1
fi
codesign --verify --deep --strict "$task_stage/Applications/Panopticon.app"
task_after=$(shasum -a 256 "$task_stage/Applications/Panopticon.app/Contents/MacOS/Panopticon" | cut -d' ' -f1)
[[ "$task_original" == "$task_after" ]]
cat > "$task_stage/bin/mv" <<'MOCK'
#!/bin/zsh
if [[ "$1" == */.Panopticon-install.*/Panopticon.app || "$1" == */.Panopticon-install.*/previous.app ]]; then exit 24; fi
exec /bin/mv "$@"
MOCK
if ZDOTDIR="$task_stage/empty-zsh" PATH="$task_stage/bin:$PATH" INSTALL_DIR="$task_stage/Applications" /bin/zsh -f ./scripts/install_app.sh; then
    printf 'FAIL: rollback failure was accepted\n' >&2; exit 1
fi
task_preserved=("$task_stage/Applications/".Panopticon-install.*/previous.app(N))
(( ${#task_preserved} == 1 ))
codesign --verify --deep --strict "${task_preserved[1]}"
task_preserved_hash=$(shasum -a 256 "${task_preserved[1]}/Contents/MacOS/Panopticon" | cut -d' ' -f1)
[[ "$task_original" == "$task_preserved_hash" ]]
printf 'PASS: temporary install, verified backup, failed install rollback, failed rollback preservation and signature\n'
