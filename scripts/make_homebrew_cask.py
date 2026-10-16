#!/usr/bin/env python3
"""Prepare a pinned, checksum-verified custom tap. Never publish or install it."""
import argparse
import hashlib
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('image', type=Path)
parser.add_argument('--output', type=Path, default=Path('build/homebrew-panopticon/Casks/panopticon.rb'))
args = parser.parse_args()
manifest = json.loads(args.image.with_suffix('.manifest.json').read_text())
version = manifest['version']
assert re.fullmatch(r'\d+\.\d+\.\d+', version), 'Expected a numeric release version'
assert manifest['architecture'] == 'universal', 'Use the universal DMG for this cask'
assert args.image.name == f'Panopticon-{version}-universal.dmg', 'Unexpected asset name'
digest = hashlib.sha256(args.image.read_bytes()).hexdigest()
assert digest == manifest['dmgSHA256'], 'DMG checksum does not match its manifest'
caveat = '' if manifest.get('notarized') and manifest.get('dmgNotarized') else '''
  caveats <<~EOS
    This build is not notarized by Apple. After the first launch attempt,
    macOS may require approval in System Settings > Privacy & Security.
  EOS
'''
content = f'''cask "panopticon" do
  version "{version}"
  sha256 "{digest}"

  url "https://github.com/anonymmized/Panopticon/releases/download/v#{{version}}/Panopticon-#{{version}}-universal.dmg"
  name "Panopticon"
  desc "Native application dock with spaces, window switching, and widgets"
  homepage "https://github.com/anonymmized/Panopticon"

  depends_on macos: ">= :ventura"

  app "Panopticon.app"

  uninstall quit: "app.newmacbar.desktop"
{caveat}end
'''
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(content)
print(f'Prepared custom-tap cask: {args.output} (not published)')
