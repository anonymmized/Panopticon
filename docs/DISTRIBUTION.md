# Локальная сборка и поставка

Версия берётся из `resources/Info.plist`. Код собирается SwiftPM; ручного списка
исходников у swiftc больше нет. `build/` и `.build/` не включаются в Git.

## Разработческая сборка

```sh
./build.sh
ARCH=x86_64 ./build.sh
ARCH=universal ./build.sh
./scripts/make_dmg.sh --skip-build
./scripts/verify_distribution.sh build/NewMacBar-0.6.0-universal.dmg
```

По умолчанию используется архитектура этого Mac и ad-hoc подпись. Такая сборка
предназначена для локальной разработки. `app-manifest.json` и manifest рядом с
DMG явно содержат `signing: adhoc`, `notarized: false`, commit, dirty-флаг и SHA-256.
Поддержка cross-compilation не означает проверку запуска на Intel или macOS 13.

DMG проверяется после создания: checksum образа, read-only mount, подпись
вложенного приложения, идентичность исполняемого файла, версия, архитектуры и
ссылка Applications. Файл `.sha256` использует имя DMG без абсолютного пути.
Для проверки копировать DMG, `.sha256` и `.manifest.json` вместе.

## Установка и откат

```sh
./build.sh install
# Или установить уже собранное приложение:
./scripts/install_app.sh
# Проверить реальный установщик в одноразовой папке:
./scripts/test_install.sh
```

Обычный выход выполняется из строки меню NewMacBar. Установщик отказывается
обновлять исполняемый файл, открытый работающим установленным процессом. Новая
копия сначала проверяется во временной папке. Предыдущая версия сохраняется в
скрытый ZIP в папке установки; при ошибке перемещения старое приложение
возвращается автоматически. Для экспериментов доступен `INSTALL_DIR`.

Для ручного отката: завершить NewMacBar, распаковать выбранный архив
`.NewMacBar-backup-….zip` в отдельную папку и вернуть `NewMacBar.app` в «Программы».
Не менять одновременно набор данных и приложение. Совместимость данных при
переходе на старую схему определяется C01; установщик данные не удаляет.

Копии старых build-бандлов остаются в `build/.previous.*`, поскольку запущенный
процесс может отображать прежний executable. Их можно удалить после завершения
соответствующих процессов. Установщик не создаёт Login Item и не сбрасывает доступ.

## Developer ID, нотариализация и release candidate

На контрольном Mac нет Developer ID Application. Текущие артефакты не
нотариализованы; Apple Development не заменяет Developer ID для внешней поставки.
Это требование описано в [документации Apple](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).

После настройки владельцем сертификата:

```sh
export SIGN_IDENTITY='Developer ID Application: …'
ARCH=universal ./build.sh
# NOTARY_PROFILE — имя профиля, заранее сохранённого владельцем в Keychain.
NOTARY_PROFILE='NewMacBar-notary' ./scripts/notarize.sh build/NewMacBar.app
./scripts/make_dmg.sh --skip-build
NOTARY_PROFILE='NewMacBar-notary' ./scripts/notarize.sh build/NewMacBar-0.6.0-universal.dmg
./scripts/verify_distribution.sh build/NewMacBar-0.6.0-universal.dmg
```

`notarize.sh` — отдельная явная команда загрузки в Apple. Она не запускается
обычной сборкой, установкой или созданием DMG. Пароли и ключи не помещать в
репозиторий или командную строку; используется профиль Keychain. Успех — статус
Accepted, затем staple/validate и Gatekeeper assessment. Основной процесс —
[notarytool/stapler Apple](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Hardened Runtime включён; единственное entitlement — Apple Events для Spotify,
Music и явно вызванных команд Finder. JIT, отключение library validation,
`get-task-allow` и sandbox-исключения не добавляются. Назначение entitlement —
[Apple Events](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events).

Для сборки только выбранного локального commit/tag, без незакоммиченных файлов:

```sh
SIGN_IDENTITY='Developer ID Application: …' ARCH=universal \
  ./scripts/package_commit.sh <commit-or-tag> ./build/candidate
# Для явной нотариализации этой поставки добавить NOTARIZE=1 и NOTARY_PROFILE.
```

Скрипт экспортирует дерево Git в отдельную папку, собирает, запускает self/panel
проверки и создаёт DMG. Ничего не пушит, не создаёт release и не отправляет GitHub
артефакты. При `NOTARIZE=1` внешняя отправка — приложение и образ в Apple.

Перед публикацией остаются: установка из quarantine на чистом Mac, работа
Automation/EventKit/AX/Login Item у подписанного приложения, обновление и откат,
целевые версии macOS/Intel/мониторы, R01/R02, тексты Claude и приёмка Gemini.
Обычный `codesign --verify` не доказывает прохождение этих сценариев.

## Возвращение Dock без панели

Из меню приложения выбрать «Вернуть системный Dock». Если меню недоступно:

```sh
/Applications/NewMacBar.app/Contents/MacOS/NewMacBar --restore-system-dock
```

Работающий экземпляр получает запрос и подтверждает результат. Если версия не
поддерживает подтверждение, команда сообщает об этом и просит завершить старый
экземпляр. Без работающего приложения восстанавливается сохранённая копия трёх
ключей `com.apple.dock`; повреждённая копия не исполняется и не удаляется.

После SIGKILL приложение ничего выполнить не может. Восстановление предлагается
на следующем запуске. Собственная панель macOS в Mission Control остаётся частью
системного интерфейса.
