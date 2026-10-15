#!/usr/bin/env python3
"""Validate current paired documentation, language separation and local links."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
paths = list(ROOT.glob('*.md')) + list((ROOT / 'docs').rglob('*.md')) + list((ROOT / 'design').rglob('*.md'))
for path in paths:
    text = path.read_text()
    relative = path.relative_to(ROOT)
    if path.name.endswith('.ru.md'):
        partner = path.with_name(path.name.replace('.ru.md', '.md'))
    else:
        partner = path.with_name(path.stem + '.ru.md')
        assert not re.search('[А-Яа-яЁё]', text), f'Cyrillic in English documentation: {relative}'
    assert partner.is_file(), f'Missing language pair: {relative}'
    assert not re.search(r'newmacbar|freedock|fashion_hab', text, re.IGNORECASE), f'Obsolete name: {relative}'
    assert not re.search(r'\b0\.[0-6]\.\d+\b', text), f'Obsolete release reference: {relative}'
    for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', text):
        if '://' in target or target.startswith('#'):
            continue
        target = target.split('#', 1)[0].strip('<>')
        assert (path.parent / target).exists(), f'Broken link in {relative}: {target}'
print(f'PASS: {len(paths) // 2} documentation pairs; English-only primary files, current names and valid links')
