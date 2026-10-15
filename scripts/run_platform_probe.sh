#!/bin/zsh
# Measure a real AppDelegate session under a fresh bundle ID, with Dock replacement
# and all integrations disabled. No edits to the user's Panopticon domain.
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 2 && "$1" == <-> && "$1" -ge 30 && "$1" -le 3600 ]] || { printf 'Usage: ./scripts/run_platform_probe.sh seconds output.json\n' >&2; exit 2; }
task_seconds="$1"
task_output="${2:A}"
task_stage=$(mktemp -d "$PWD/build/.platform-probe.XXXXXX")
task_id="app.newmacbar.platformreview.$(uuidgen | tr '[:upper:]' '[:lower:]')"
task_app="$task_stage/PanopticonQA.app"
task_pid=''
cleanup() {
    if [[ -n "$task_pid" ]] && kill -0 "$task_pid" 2>/dev/null; then kill -TERM "$task_pid"; fi
    /usr/bin/defaults delete "$task_id" >/dev/null 2>&1 || true
    rm -rf "$task_stage" "$HOME/Library/Application Support/$task_id"
}
trap cleanup EXIT
[[ -d build/Panopticon.app ]] || { printf 'Build first with ./build.sh\n' >&2; exit 1; }
ditto build/Panopticon.app "$task_app"
/usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $task_id" "$task_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set CFBundleName PanopticonQA' "$task_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set CFBundleDisplayName PanopticonQA' "$task_app/Contents/Info.plist"
codesign --force --sign - --options runtime --timestamp=none --entitlements resources/Panopticon.entitlements "$task_app"
/usr/bin/defaults write "$task_id" layoutVersion -int 2
/usr/bin/defaults write "$task_id" ui.onboardingCompleted -bool true
/usr/bin/defaults write "$task_id" pinned -array /System/Library/CoreServices/Finder.app /System/Applications/Calendar.app /System/Applications/Music.app '/System/Applications/System Settings.app'
for task_flag in replaceDock calendarEventsEnabled showRunning showBadges showSpaces showTrash showSettingsButton launcherEnabled autoHide followMouse; do
    /usr/bin/defaults write "$task_id" "$task_flag" -bool false
done
/usr/bin/defaults write "$task_id" widget -string none
/usr/bin/defaults write "$task_id" secondaryWidget -string none
/usr/bin/defaults write "$task_id" edge -string left
mkdir -p "${task_output:h}"
task_mode=idle; if [[ "${SMOKE_LIFECYCLE:-0}" == 1 ]]; then task_mode=lifecycle; fi
printf 'Starting isolated %s probe: 15-second warmup + %s seconds\n' "$task_mode" "$task_seconds"
"$task_app/Contents/MacOS/Panopticon" --performance-probe "$task_seconds" "$task_output" > "$task_stage/session.log" 2>&1 &
task_pid=$!
if [[ "${SMOKE_LIFECYCLE:-0}" == 1 ]]; then
    python3 - "$task_app/Contents/MacOS/Panopticon" "$task_pid" <<'SMOKE'
import os, subprocess, sys, time
binary, owner=sys.argv[1], int(sys.argv[2]); time.sleep(1)
restored=subprocess.run([binary,'--restore-system-dock'],capture_output=True,text=True,timeout=8,check=True)
if 'восстановлен' not in restored.stdout: raise SystemExit('Owner did not acknowledge Dock recovery request: '+restored.stdout.strip())
subprocess.run([binary,'--settings'],capture_output=True,text=True,timeout=8,check=True)
os.kill(owner,0)
print('PASS: live owner restore acknowledgement and second-instance activation')
SMOKE
fi
if wait "$task_pid"; then task_pid=''
else
    task_pid=''; cp "$task_stage/session.log" "${task_output%.json}.failure.log"
    printf 'Probe failed; technical log: %s\n' "${task_output%.json}.failure.log" >&2; exit 1
fi
[[ -f "$task_output" ]] || { cat "$task_stage/session.log"; printf 'Probe did not produce a report\n' >&2; exit 1; }
if /usr/bin/defaults read "$task_id" platform.activeSession >/dev/null 2>&1; then printf 'Session marker was not cleared on normal exit\n' >&2; exit 1; fi
python3 - "$task_output" "${SMOKE_LIFECYCLE:-0}" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1]); value=json.loads(path.read_text())
value['scenario']='Lifecycle smoke with settings open; not an idle measurement' if sys.argv[2]=='1' else 'Visible native panel, 4 installed apps, widgets/integrations/autoHide/followMouse off, settings closed, isolated bundle ID'
path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
print(path.read_text())
PY
