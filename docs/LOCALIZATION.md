# Localization

[English](LOCALIZATION.md) | [Russian](LOCALIZATION.ru.md)

The sidebar language control offers English, Russian and System. The selection is
saved separately from spaces and appearance profiles. System chooses the first
supported macOS language, falling back to English. Invalid saved choices normalize
to System. Calendar month and weekday names use the selected locale.

## Catalogs and packaging

`Sources/Panopticon/Resources/en.json` and `ru.json` contain matching translation
keys. The SwiftPM target processes these resources for command-line builds.
`build_app.sh` copies both catalogs into the app Resources directory. Permission
usage descriptions have matching `resources/en.lproj/InfoPlist.strings` and
`resources/ru.lproj/InfoPlist.strings` files.

`L(...)` separates a stable source key from interpolation arguments. Catalog values
may reorder numbered placeholders. Replacement is one pass: user content containing
braces, percent signs or Unicode is preserved literally. App, collection, shortcut
and item counts use language-specific singular and plural forms.

SwiftUI surfaces observe `Localization`. Native menus and panel accessibility labels
refresh on its change notification. A language change does not reveal a hidden panel,
request a permission or rewrite user-entered names. Controller-owned status messages
can be retranslated; operating-system errors retain the text supplied by macOS.

Never translate app names, track metadata, event titles, paths, user-authored space
or profile names, schema identifiers or keyboard-layout maps. Default space names
are localized only when created.

## Checks

```sh
python3 scripts/check_localizations.py
swift build -c release
.build/release/Panopticon --self-test
```

Checks cover every literal translation call, catalog parity, English coverage,
placeholder preservation, plural forms, fallback order, persistence and literal
user data. Model self-tests run in both interface languages. AppKit tests cover
native context menus and panel behavior.

Documentation is paired by filename. English Markdown must contain no Cyrillic;
Russian Markdown uses `.ru.md`. Run `scripts/check_documentation.py` before committing.
