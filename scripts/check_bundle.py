#!/usr/bin/env python3
"""Check an app's identity and resources without launching it or requesting access."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re

parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path)
parser.add_argument('--current-source', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
contents = args.app / 'Contents'
info = plistlib.loads((contents / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'app.newmacbar.desktop', 'Settings identity changed'
assert info['CFBundleExecutable'] == info['CFBundleName'] == info['CFBundleDisplayName'] == 'Panopticon'
assert re.fullmatch(r'\d+\.\d+\.\d+', info['CFBundleShortVersionString']), 'Invalid app version'
assert str(info['CFBundleVersion']).isdigit(), 'Invalid build number'
assert info['LSMinimumSystemVersion'] == '13.0' and info['LSUIElement'] is True
assert os.access(contents / 'MacOS/Panopticon', os.X_OK), 'Executable missing'
assert (contents / 'Resources/AppIcon.icns').stat().st_size > 0, 'App icon missing'
catalogs = {}
for code in ['en', 'ru']:
    catalog = json.loads((contents / f'Resources/{code}.json').read_text())
    assert len(catalog) > 600 and all(catalog.values()), f'Incomplete {code} catalog'
    catalogs[code] = catalog
    strings = contents / f'Resources/{code}.lproj/InfoPlist.strings'
    assert 'NSCalendarsFullAccessUsageDescription' in strings.read_text(), f'Missing {code} permission text'
    if args.current_source:
        source = json.loads((root / f'Sources/Panopticon/Resources/{code}.json').read_text())
        assert source == catalog, f'Stale {code} catalog in bundle'
assert catalogs['en'].keys() == catalogs['ru'].keys(), 'Catalog keys differ'
assert not any(re.search('[А-Яа-яЁё]', value) for value in catalogs['en'].values()), 'English catalog contains Cyrillic'
if args.current_source:
    source = plistlib.loads((root / 'resources/Info.plist').read_bytes())
    assert source == info, 'Stale Info.plist in bundle'
print(f"PASS: bundle identity, executable, icon, version {info['CFBundleShortVersionString']} and both language resources")
