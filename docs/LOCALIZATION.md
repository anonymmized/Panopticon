# Panopticon naming and localization

The product, SwiftPM target, executable, source directory, app bundle, CI artifacts
and DMG are named **Panopticon**. `README.md` is the English entry point;
`README.ru.md` is the Russian counterpart.

The existing `app.newmacbar.desktop` bundle identifier is deliberately retained.
It owns the previous preferences, macOS permissions and system Dock recovery
backup. Changing the display name does not require migrating these domains.
Activation notifications keep the same identity so an old running copy and the
renamed app still cooperate. FreeDock remains the name of the external legacy
format, not an alternative name for the current product. Historical copyright
attribution is retained.

## Translation files

- `Sources/Panopticon/Resources/en.json`: English translations.
- `Sources/Panopticon/Resources/ru.json`: Russian translations.
- `resources/en.lproj/InfoPlist.strings` and `resources/ru.lproj/InfoPlist.strings`:
  localized macOS permission descriptions and app names.

SwiftPM processes the JSON resources into its resource bundle. `build_app.sh`
copies the same files into the native app's Resources directory, along with both
InfoPlist localizations. The base Info.plist uses English and declares both
supported languages. No translation services or network requests are used.

## Interface strings

Call `L("Настройки…")` for static text and `L("Открыть \(name)")` for interpolation.
Russian source strings serve as stable catalog keys; they are not shown in the
English interface. App, collection, shortcut and item counts use English and Russian plural forms.
Interpolation builds a key such as `Открыть {0}`, preserving
arguments separately. Catalogs may reorder numbered placeholders. Substitution
uses one pass: user content containing `{1}`, percent signs or Unicode is never
interpreted as another placeholder.

Do not translate app names, track metadata, event titles, paths, user-entered
space/profile names, protocol constants or search keyboard-layout maps.
Built-in default space names are localized only when first created; switching
language never renames persisted spaces.

Add every key to both JSON files, preserving the same numbered placeholders.
SwiftUI surfaces observe `Localization.shared` so already-open settings, editors,
search and widget popovers update without discarding their state. AppKit menus
and accessibility labels rebuild on `Panopticon.languageChanged`. The callback
only refreshes display content; it never reveals the panel or changes Dock settings.

`interfaceLanguage` stores `system`, `en` or `ru` in the existing preferences
domain, independently of spaces and profiles. Invalid values normalize to System.
System chooses the first supported language in macOS's preference order, then
falls back to English. Calendar formatters use the selected language. OS-owned
errors and dialogs remain under macOS control.

## Verification

```sh
python3 scripts/check_localizations.py
swift build -c release
.build/release/Panopticon --self-test
.build/release/Panopticon --panel-self-test
./build.sh
build/Panopticon.app/Contents/MacOS/Panopticon --self-test
codesign --verify --deep --strict build/Panopticon.app
```

Localization tests use an isolated UserDefaults suite. They check catalog parity,
English coverage, interpolation placeholders, literal user content, fallback order,
explicit language selection, preference reload, plural forms, dates and the retained identity.
The full model self-test suite runs under both English and Russian; panel tests
also check actual native context-menu titles and accessibility labels in both languages.
No permissions are requested and no real preferences are migrated by these tests.

Manual review: switch English → Русский → System, visit all settings sections,
open search and widget popovers, check native panel and menu-bar menus, and restart
to check persistence. Confirm that existing space and profile names are unchanged.
