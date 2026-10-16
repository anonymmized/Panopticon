# Дистрибуция

[Английский](DISTRIBUTION.md) | [Русский](DISTRIBUTION.ru.md)

Для установки используй DMG из [последнего релиза](https://github.com/anonymmized/Panopticon/releases/latest).
Ниже описана упаковка для разработчиков. Публикация версии и Homebrew tap —
в [инструкции выпуска](RELEASE.ru.md).

## Локальные сборки

```sh
./build.sh
ARCH=x86_64 ./build.sh
ARCH=universal ./build.sh
```

Источник версии — `resources/Info.plist`. Сборка создаёт промежуточный пакет, добавляет
английские и русские ресурсы, подписывает и проверяет результат. Прежняя локальная сборка
остаётся целой. `build/app-manifest.json` содержит версию, архитектуру, коммит, состояние
рабочего дерева, SHA-256 исполняемого файла и тип подписи.

## Установка и откат

Закрой установленное приложение, затем запусти `./scripts/install_app.sh` или
`./build.sh install`. Установщик не заменяет работающий файл, проверяет копию,
сохраняет ZIP и возвращает прежний пакет при ошибке завершающего перемещения.
Защита работает и при смене имени файла. Через `INSTALL_DIR` можно выбрать свой каталог.

`./scripts/test_install.sh` проверяет установку, копию и откат во временных папках,
не меняя настоящую папку Applications.

## Образ диска

```sh
ARCH=universal ./build.sh
./scripts/make_dmg.sh --skip-build
./scripts/verify_distribution.sh build/Panopticon-*-universal.dmg
```

В образе находятся приложение и ссылка на Applications. Рядом сохраняются контрольная
сумма и манифест. Проверка подключает образ только для чтения, сверяет пакет, хеши,
архитектуры и подпись, затем отключает образ.

## Developer ID и нотариализация

Первый скачиваемый пакет использует подпись ad-hoc и не нотариализован Apple.
Первый запуск может потребовать подтверждения в «Конфиденциальность и безопасность».
Подпись Developer ID и нотариализацию можно добавить позже; для них владельцу нужны
сертификат Developer ID и сохранённый профиль notarytool в Keychain.

```sh
export SIGN_IDENTITY='Developer ID Application: YOUR IDENTITY'
ARCH=universal ./build.sh
NOTARY_PROFILE='YOUR KEYCHAIN PROFILE' ./scripts/notarize.sh build/Panopticon.app
./scripts/make_dmg.sh --skip-build
NOTARY_PROFILE='YOUR KEYCHAIN PROFILE' ./scripts/notarize.sh build/Panopticon-*-universal.dmg
./scripts/verify_distribution.sh build/Panopticon-*-universal.dmg
```

Команда нотариализации явно отправляет файлы в Apple. Остальные команды сборки и упаковки
ничего не загружают. Учётные данные хранятся в Keychain, а не исходниках. Не называй
ad-hoc сборку нотариализованной и не подменяй нотариализацию удалением карантина.
