# Публикация Panopticon 1.0

[English](RELEASE.md) | [Русский](RELEASE.ru.md)

Версия **1.0.0**, сборка **11**. Локальная упаковка ничего не публикует.
Релиз готовится как универсальный DMG для macOS 13+ без нотариализации Apple.
Описание версии должно явно сообщать об одобрении первого запуска и ограничениях.

## Проверка и упаковка

Выполни проверки из [разработки](DEVELOPMENT.ru.md). Проверь настоящую панель,
настройки и установку на поддерживаемых Mac. Подключение календаря, управления
музыкой и Универсального доступа проверяется по действию пользователя; тесты
разрешения не выдают. Фактический объём проверок — в [валидации](VALIDATION.ru.md).

```sh
./scripts/check_release.sh
ARCH=universal ./build.sh
./scripts/test_install.sh
./scripts/make_dmg.sh --skip-build
./scripts/verify_distribution.sh build/Panopticon-1.0.0-universal.dmg
```

Сохрани вместе три файла:

- `build/Panopticon-1.0.0-universal.dmg`
- `build/Panopticon-1.0.0-universal.dmg.sha256`
- `build/Panopticon-1.0.0-universal.manifest.json`

Манифест содержит версию, сборку, исходный коммит, состояние Git, архитектуры,
подпись и хеши. Публикуй проверенный чистый коммит и соответствующий ему образ.
Установщики и результаты сборки не добавляются в Git.

## Слияние и тег

Владелец выполняет команды после проверки ветки. При ошибке остановись;
существующий тег релиза не перезаписывай.

```sh
git switch main
git pull --ff-only origin main
git merge --ff-only codex/v1-window-switcher
git push origin main
git tag -a v1.0.0 -m "Panopticon 1.0.0"
git push origin v1.0.0
```

Fast-forward сохраняет тот же проверенный коммит, который записан в манифесте DMG.
Если main успел измениться, остановись, объедини и проверь исходники, затем пересобери
и проверь итоговый пакет перед тегом. Не используй образ из другого дерева исходников.

## Через сайт GitHub

1. Открой [Releases](https://github.com/anonymmized/Panopticon/releases) и нажми
   **Draft a new release**.
2. Выбери отправленный тег **v1.0.0**. Название релиза — **Panopticon 1.0.0**.
3. Вставь [английское описание версии](releases/v1.0.0.md). При желании добавь
   [русский текст](releases/v1.0.0.ru.md) отдельным языковым разделом.
4. Перетащи DMG, контрольную сумму и манифест в область загрузки файлов релиза.
5. Включи **Set as the latest release**, оставь **pre-release** выключенным,
   проверь файлы и нажми **Publish release**.

После публикации [ссылка на последнюю версию](https://github.com/anonymmized/Panopticon/releases/latest)
будет открывать этот релиз. Кнопка README использует её же: при следующих стабильных
выпусках ссылку менять не нужно. Отправка одного тега не загружает DMG.

Если настроен GitHub CLI, владелец может вместо сайта выполнить:

```sh
gh release create v1.0.0 --verify-tag --latest \
  --title "Panopticon 1.0.0" --notes-file docs/releases/v1.0.0.md \
  build/Panopticon-1.0.0-universal.dmg \
  build/Panopticon-1.0.0-universal.dmg.sha256 \
  build/Panopticon-1.0.0-universal.manifest.json
```

## Собственный Homebrew tap

После создания и проверки итогового DMG:

```sh
python3 scripts/make_homebrew_cask.py build/Panopticon-1.0.0-universal.dmg
ruby -c build/homebrew-panopticon/Casks/panopticon.rb
```

Команда только создаёт локальный cask. После публикации релиза создай публичный
репозиторий **homebrew-panopticon** под своим аккаунтом и добавь полученный файл
как **Casks/panopticon.rb**. Сначала проверь ссылку и SHA-256. Тогда установка станет такой:

```sh
brew install --cask anonymmized/panopticon/panopticon
```

При обновлении сгенерируй cask из нового проверенного DMG, опубликуй релиз и обнови tap.
После публикации не заменяй файл образа с уже опубликованной контрольной суммой.
Это собственный tap, а не попадание в официальный каталог Homebrew.
Cask сохраняет настройки, завершает приложение при удалении и не снимает карантин
или разрешения автоматически.

## Ограничения релиза

В Mission Control остаётся системный Dock. Выбор окон требует Универсального
доступа и показывает окна, а не вкладки браузера или снимки экрана. Встроенного
автообновления нет. Подпись Developer ID и нотариализацию можно добавить позже
по [инструкции распространения](DISTRIBUTION.ru.md); для этого пакета они не заявлены.
