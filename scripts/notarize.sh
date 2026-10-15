#!/bin/zsh
# Explicit opt-in: this command uploads a Developer ID-signed app to Apple's notary service.
# Credentials stay in the owner's Keychain; passwords must never be put in this script.
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 1 ]] || { printf 'Usage: NOTARY_PROFILE=keychain-profile ./scripts/notarize.sh path/to/App.app-or-image.dmg\n' >&2; exit 2; }
: "${NOTARY_PROFILE:?Set the name of a previously configured notarytool Keychain profile}"
task_app="${1:A}"
[[ (-d "$task_app" && "$task_app" == *.app) || (-f "$task_app" && "$task_app" == *.dmg) ]] || { printf 'Expected an application bundle or disk image\n' >&2; exit 2; }
codesign --verify --deep --strict "$task_app"
task_details=$(codesign --display --verbose=4 "$task_app" 2>&1)
[[ "$task_details" == *'Authority=Developer ID Application:'* ]] || { printf 'Developer ID is required\n' >&2; exit 1; }
if [[ "$task_app" == *.app && "$task_details" != *runtime* ]]; then printf 'Hardened Runtime is required\n' >&2; exit 1; fi
task_stage=$(mktemp -d "${TMPDIR:-/private/tmp}/newmacbar-notary.XXXXXX")
trap 'rm -rf "$task_stage"' EXIT
task_submission="$task_app"
if [[ "$task_app" == *.app ]]; then ditto -c -k --keepParent "$task_app" "$task_stage/NewMacBar.zip"; task_submission="$task_stage/NewMacBar.zip"; fi
xcrun notarytool submit "$task_submission" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$task_stage/result.json"
python3 - "$task_stage/result.json" <<'PY'
import json, sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted. Review the submission in notarytool history/log.')
print('Apple notary service: Accepted')
PY
xcrun stapler staple "$task_app"
xcrun stapler validate "$task_app"
if [[ "$task_app" == *.app ]]; then spctl --assess --type execute --verbose=2 "$task_app"
else spctl --assess --type open --context context:primary-signature --verbose=2 "$task_app"; fi
# Keep packaging metadata aligned with the stapled artifact.
if [[ "$task_app" == "$PWD/build/NewMacBar.app" ]]; then
    python3 - <<'PY'
import json, pathlib
path=pathlib.Path('build/app-manifest.json')
value=json.loads(path.read_text()); value['notarized']=True
path.write_text(json.dumps(value, indent=2, sort_keys=True)+'\n')
PY
fi
if [[ "$task_app" == *.dmg ]]; then
    python3 - "$task_app" <<'UPDATE'
import hashlib, json, pathlib, sys
image=pathlib.Path(sys.argv[1]); metadata=image.with_suffix('.manifest.json')
if metadata.exists():
    value=json.loads(metadata.read_text()); value['dmgNotarized']=True
    value['dmgSHA256']=hashlib.sha256(image.read_bytes()).hexdigest()
    metadata.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
    image.with_name(image.name+'.sha256').write_text(value['dmgSHA256']+'  '+image.name+'\n')
UPDATE
fi
printf 'Notarized and stapled: %s\n' "$task_app"
