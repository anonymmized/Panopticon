# История изменений

## Unreleased — Panopticon

- Renamed the app, executable, Swift package, source directory and distribution artifacts to Panopticon.
- Added English and Russian interface catalogs, live System / English / Русский selection and localized calendar dates.
- Added English as the primary README and a Russian README, plus localized macOS permission descriptions.
- Preserved the existing bundle ID, settings, privacy grants and Dock recovery data across the rename.
- Updated installation to back up the legacy app name and reject replacement of a running copy.


## [0.5.0] — 2026-10-14

Общая исходная база Panopticon и FreeDock перед параллельной разработкой.

- Пространства приложений, папок, сайтов и коллекций с привязкой к рабочим столам.
- Панель у четырёх краёв, следование за экраном курсора, 8 тем.
- Переключение пространств прокруткой, ⌃⌥1–9 и ⌃⌥←/→; скрытие по ⌃⌥D.
- Папки-стопки, файлы и ссылки, корзина, перемещение приложений между наборами.
- Бейджи и список окон через необязательный Универсальный доступ.
- Поиск пространств, действий и ярлыков из других наборов.
- Импорт config.json FreeDock без удаления текущих пространств и профилей.
- Сохранены календарные связи, профили, два виджета, плеер, таймер и исправления A0.
- SwiftPM, сборка и установка приложения, локальная упаковка DMG с SHA-256.
- Регрессии переноса данных и тест панели на четырёх краях.
- Кеши и собранные бинарники исключены из исходного дерева Git.
