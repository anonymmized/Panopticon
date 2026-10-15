#!/usr/bin/env python3
"""Check local translation resources and Swift L(...) call coverage; no network."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'Sources' / 'Panopticon'


def literal(source, start):
    """Read a Swift string, keeping interpolated expressions out of its key."""
    index = start + 1
    parts, arguments = [], []
    text = ''
    while index < len(source):
        if source[index] == '"':
            parts.append(text)
            key = ''.join(part + (f'{{{n}}}' if n < len(arguments) else '')
                          for n, part in enumerate(parts))
            return index + 1, key
        if source[index:index + 2] == '\\(':
            parts.append(text)
            text = ''
            index += 2
            begin, depth = index, 1
            while depth:
                if source[index] == '"':
                    index = literal(source, index)[0]
                    continue
                if source[index] == '(':
                    depth += 1
                elif source[index] == ')':
                    depth -= 1
                index += 1
            arguments.append(source[begin:index - 1])
        elif source[index] == '\\':
            # Interface strings use the JSON-compatible subset of Swift escapes.
            text += json.loads('"' + source[index:index + 2] + '"')
            index += 2
        else:
            text += source[index]
            index += 1
    raise ValueError('Unterminated string')


def main():
    catalogs = {code: json.loads((SOURCE / 'Resources' / f'{code}.json').read_text())
                for code in ['en', 'ru']}
    assert catalogs['en'].keys() == catalogs['ru'].keys(), 'Catalog keys differ'
    for key in catalogs['en']:
        tokens = lambda value: sorted(re.findall(r'\{[0-9]+\}', value))
        for code, catalog in catalogs.items():
            assert catalog[key], f'Empty {code} translation: {key}'
            assert tokens(key) == tokens(catalog[key]), f'Interpolation mismatch: {key}'
        assert not re.search('[А-Яа-яЁё]', catalogs['en'][key]), f'Untranslated English: {key}'
    used = set()
    for path in SOURCE.glob('*.swift'):
        source = path.read_text()
        for match in re.finditer(r'\bL\(\s*"', source):
            _, key = literal(source, match.end() - 1)
            assert key in catalogs['en'], f'Missing key in {path.name}: {key}'
            used.add(key)
    print(f'PASS: {len(catalogs["en"])} bilingual entries; {len(used)} Swift translation keys covered')


if __name__ == '__main__':
    main()
