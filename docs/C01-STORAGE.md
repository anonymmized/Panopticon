# C01 — предложение: версионированное хранение, резервирование и миграции

**Статус:** черновик v2 для согласования (волна 0). Кода нет — по плану код C01 начинается после P01.
**v2:** сверено с дизайном Gemini (`design/` G01–G04, `design_tokens.json`) — см. раздел 11.
**Автор:** Claude. **Ревью:** Codex (реализуемость, жизненный цикл), владелец (решения из раздела 9).
**База анализа:** `main` @ `53dd4a3` (NewMacBar 0.5.0).
**Проверено:** только чтение исходников. На macOS ничего не запускалось — **не проверено**.

---

## 1. Как настройки хранятся сейчас (0.5.0)

### 1.1. Где

Всё лежит в `UserDefaults.standard`, домен `app.newmacbar.desktop`
(`~/Library/Preferences/app.newmacbar.desktop.plist`). Запись — `BarModel.save()`
(`Sources/NewMacBar/Model.swift`), чтение — `BarModel.init(defaults:observe:)`.

### 1.2. Полный перечень ключей

| Ключ | Тип в plist | Дефолт | Нормализация при чтении | Владелец сейчас |
|---|---|---|---|---|
| `spaces` | Data (JSON `[BarSpace]`) | 3 пространства | дедупликация id, `prefix(30)`, `label()` | Model |
| `selectedSpaceID` | String | id первого | должен существовать | Model |
| `pinned` | [String] пути | из системного Dock | **фильтр `fileExists`** | Model (legacy, дублирует `spaces`) |
| `quickLinks` | Data (JSON `[QuickLink]`) | `[]` | — | Model (legacy, дублирует `spaces`) |
| `collections` | Data (JSON `[AppCollection]`) | `[]` | — | Model (legacy, дублирует `spaces`) |
| `profiles` | Data (JSON `[DockProfile]`) | `[]` | при применении — `sanitized()` | Model |
| `selectedCalendarIDs` | [String] | `[]` | — | Model |
| `edge` | String | `bottom` | `choice` | Model |
| `showSpaces`, `showTrash`, `showRunning`, `showLabels`, `showSeparator`, `showSettingsButton`, `showBadges` | Bool | см. код | — | Model |
| `autoSwitchDesktops`, `scrollToSwitch`, `followMouse`, `barVisible`, `autoHide`, `replaceDock` | Bool | см. код | — | Model |
| `iconSize`, `iconSpacing`, `cornerRadius`, `hoverLift`, `magnification`, `bottomOffset`, `opacity` | Double | 36/8/20/7/1.35/10/0.08 | `ProfileAppearance.sanitized()` | Model |
| `widget`, `secondaryWidget`, `widgetStyle`, `widgetAccent` | String | clock/none/wide/violet | `choice` | Model |
| `widgetWidth`, `widgetOpacity` | Double | 158/0.28 | диапазон | Model |
| `theme`, `hoverStyle`, `launchStyle`, `indicatorStyle` | String | dark/lift/bounce/dot | `choice` | Model |
| `hoverGlow`, `reduceMotion`, `clockSeconds` | Bool | true/false/false | — | Model |
| `clockFormat`, `clockAction`, `playerPreference` | String | 24h/open/auto | `choice` | Model |
| `timerMinutes` | Double | 25 | 5…90 | Model |
| `calendarDestination`, `calendarAppPath`, `calendarWebURL` | String | system/""/google | `choice` для destination | Model |
| `calendarEventsEnabled` | Bool | false | — | Model |
| `launcherEnabled` | Bool | true | — | Model |
| `launcherShortcutChoice` | String | controlOptionSpace | `choice` | Model |
| `screenIndex` | Int | 0 | `max(0, …)` | Model |
| `recentAppPaths` | [String] | `[]` | `prefix(12)` | Model, пишется вне `save()` |
| `layoutVersion` | Int | 0 → 2 | разовая миграция в `main.swift` | main |
| `focusSession` | Dictionary | — | диапазоны | FocusTimer |
| `systemDockBackup` | Dictionary | — | — | DockIntegration |

Состояние времени выполнения, которое **не** сохраняется: `running`, `items`, `badges`,
`currentDesktop`, `launcherShortcutAvailable`, `activeBundleID`.

### 1.3. Найденные проблемы (кандидаты в дефекты; подтвердить на Mac)

| # | Где | Что | Сценарий | Уровень (12.4) |
|---|---|---|---|---|
| D1 | `Model.swift:136, 150`, `Spaces.swift` `selectSpace` | При загрузке и при смене пространства пути фильтруются по `fileExists`/`bundleID`. Следующий `save()` → `snapshotSpace()` записывает отфильтрованный список обратно. | Приложение на отключённом внешнем диске: запуск → любое изменение → элемент **навсегда** пропал из набора. Нарушает инвариант 3 и DAT-04. | **S0** (потеря данных) |
| D2 | `Actions.swift:157` `applyProfile` | Тот же фильтр при применении профиля. | Профиль с приложением на внешнем диске теряет его при применении. | S1 |
| D3 | `Model.swift:142` | `prefix(30)` при загрузке молча обрезает пространства сверх лимита, следующий `save()` их стирает. | Пространства > 30 (старая сборка, ручная правка, будущий лимит). | S1 |
| D4 | `Model.swift:243–292` | `save()` пишет ~50 ключей по одному на **каждый** `didSet` (кроме `batch`). Нет единицы записи. | Авария между ключами → смесь старого и нового состояния; ползунок → десятки полных записей в секунду. | S2 |
| D5 | `pinned`/`quickLinks`/`collections` | Хранятся и на верхнем уровне, и внутри `spaces[selected]`. Два источника правды. | Рассинхрон при ошибке `snapshotSpace`; путаница при миграции. | S2 |
| D6 | — | Нет версии схемы. Есть только `layoutVersion = 2` в `main.swift`. | Невозможно отличить «старые данные» от «данные будущей версии». | S2 |
| D7 | `ProfileArchive.decode` | Фильтр `hasSuffix(".app")` + `prefix(200)` молча отбрасывает лишнее без отчёта. | Импорт профиля теряет элементы, пользователь не знает. | S2 |
| D8 | `recentAppPaths` | Пишется в обход `save()`; размер не нормализуется при чтении. | Мелочь, но это второй путь записи. | S3 |

D1 стоит исправить даже раньше C01 — отдельным минимальным фиксом (см. 9, вопрос Q1).

---

## 2. Цели C01

1. Одно авторитетное хранилище — атомарный JSON-файл. UserDefaults остаётся для миграции, Dock-backup и мелких системных флагов.
2. Явная версия схемы и детерминированные миграции.
3. Ни один сбой (повреждение, нет места, отказ записи, авария, будущая версия) не уничтожает последнюю рабочую копию.
4. Недоступные пути никогда не удаляются при чтении и записи.
5. Нет записи в idle. Дебаунс правок. Обязательный сброс на диск при выходе и сне.
6. `BarModel` остаётся фасадом для UI — P01 и UI-задачи Codex не переписываются.

---

## 3. Файлы на диске

```
~/Library/Application Support/app.newmacbar.desktop/
  settings.json                     ← авторитетное состояние (SettingsSnapshot)
  runtime.json                      ← таймер фокуса, недавние приложения (не экспортируется)
  backups/
    settings-2026-10-14T21-05-33Z.json   ← ротация, до 10 штук
    pre-migration-v0-2026-10-14T21-05-33Z.json   ← перед миграцией, не ротируется
    pre-import-2026-10-14T21-05-33Z.json         ← перед импортом, хранится 5 последних
  broken/
    settings-2026-10-14T21-05-33Z.json   ← нечитаемый файл, сохранён для диагностики
```

Каталог по bundle id, а не по названию приложения, — переименование в P00 его не затрагивает.

**Остаётся в UserDefaults:**
- `systemDockBackup` — **не** входит в `SettingsSnapshot`, экспорт и импорт. Его нельзя заменить импортом настроек (требование C01 → X01).
- `settingsStorage` = `"file-v1"` — маркер, что миграция выполнена.
- Старые ключи 0.5.0 **не удаляются** в 1.0. Это даёт откат на 0.5.0 (без изменений, сделанных после миграции). Удаление — отдельной задачей после 1.0.

---

## 4. Схема `SettingsSnapshot` v1

Принципы: строгие enum вместо строк; у каждого элемента стабильный ID; дефолт у каждого поля;
неизвестные значения enum → дефолт + предупреждение, а не ошибка всего файла.

```swift
struct SettingsSnapshot: Codable, Equatable {
    static let currentSchema = 1
    var schemaVersion: Int                    // = currentSchema при записи
    var writtenBy: String                     // "NewMacBar 0.6.0 (123)" — диагностика
    var spaces: [SpaceRecord]                 // 1...SpaceLimits.max
    var selectedSpaceID: String
    var profiles: [ProfileRecord]
    var appearance: AppearanceSettings
    var behavior: BehaviorSettings
    var widgets: WidgetSettings
    var calendar: CalendarSettings
    var launcher: LauncherSettings
    var shortcuts: [ShortcutBinding]           // C07: реестр, редактируется HotkeyRecorder (G02)
}

/// v2: явное различие «все календари» и «ни одного» (G03 3.2, состояние 3).
enum CalendarSelection: Codable, Equatable {
    case all                                  // 0.5.0: пустой selectedCalendarIDs означал «все»
    case only(Set<String>)                    // .only([]) = пользователь снял все галочки
}

struct SpaceRecord: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var symbol: String
    var desktop: Int?                         // 1...30, уникален среди пространств
    var items: [ItemRecord]                   // приложения + файлы + папки + сайты, в порядке панели
    var collections: [CollectionRecord]
}

struct ItemRecord: Codable, Equatable, Identifiable {
    var id: String                            // UUID, стабилен при перестановке (нужен C02/undo)
    var kind: ItemKind                        // .app | .file | .folder | .web
    var location: String                      // абсолютный путь или http(s) URL
    var name: String?                         // nil = брать из системы
    var bookmark: Data?                       // зарезервировано; в v1 не заполняется (Q4)
}

struct CollectionRecord: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var symbol: String
    var itemIDs: [String]                     // ссылки на ItemRecord? — см. Q3
    var locations: [String]                   // v1: пути .app, как в 0.5.0
}

struct ProfileRecord: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var appearance: AppearanceSettings
    var items: [ItemRecord]                   // снимок текущего набора (как в 0.5.0)
    var collections: [CollectionRecord]
    var spaces: [SpaceRecord]?                // v2: G01 «по выбору при импорте — список пространств»; nil = не сохранялись (Q9)
}
```

`AppearanceSettings`, `BehaviorSettings`, `WidgetSettings`, `CalendarSettings`, `LauncherSettings` —
структуры полей из таблицы 1.2, сгруппированные по смыслу, с enum-типами
(`DockEdge`, `DockTheme`, `HoverStyle`, `LaunchStyle`, `IndicatorStyle`, `WidgetKind`, `WidgetStyle`,
`WidgetAccent`, `ClockFormat`, `ClockAction`, `PlayerPreference`, `CalendarDestination`, `LauncherShortcut`).
Строковые rawValue enum-ов совпадают с 0.5.0 и с ID в `design_tokens.json` (темы, акценты) — G02 требует
обратной совместимости идентификаторов.

**Лимиты (`SettingsLimits`, согласовано с G01 раздел 5):** пространств 30, коллекций 50, приложений в коллекции 200,
элементов в пространстве 500, профилей 50. Превышение при загрузке/импорте — предупреждение и отчёт, не молчаливое
удаление (D3, D7).
Диапазоны чисел — из `SettingsRules`/`sanitized()`, вынесенные в одно место (`SettingsLimits`).

**Разделение пространства и профиля (D5, требование C02):** в v1 у панели нет отдельных верхнеуровневых
`pinned/quickLinks/collections`. Текущий набор — это `spaces[selectedSpaceID].items`.
Профиль хранит **снимок** набора и оформление, но не подключения календаря и не правила пространств.

### 4.1. Декодирование

Каждая структура — свой `init(from:)` с `decodeIfPresent ?? default`. Неизвестный enum — дефолт +
`LoadWarning.unknownValue(path:value:)`. Битый элемент массива (например, `ItemRecord` без `location`)
пропускается с предупреждением, остальные элементы сохраняются (`LossyArray`).

### 4.2. Нормализация (`normalized() -> (SettingsSnapshot, [LoadWarning])`)

- числа — в диапазоны, `NaN/inf` → дефолт;
- дубли ID пространств/элементов → новые ID, **не удаление**;
- `selectedSpaceID` вне списка → первое пространство;
- `desktop` дублируется → остаётся у первого, у остальных nil + предупреждение;
- пространств больше лимита → лишние **не удаляются**, а помечаются `LoadWarning.overLimit` и показываются
  в настройках (решение Q2);
- **существование файлов не проверяется никогда** (D1).

---

## 5. API хранилища (контракт для Codex)

```swift
enum LoadOutcome: Equatable {
    case fresh                                // файла и старых ключей нет — первый запуск
    case loaded
    case migrated(fromSchema: Int)            // 0 = UserDefaults 0.5.0
    case recovered(from: URL, reason: RecoveryReason)
    case futureVersion(found: Int)            // открыт только для чтения
}
enum RecoveryReason: Equatable { case unreadable, decodeFailed, emptyFile }

struct LoadResult {
    var snapshot: SettingsSnapshot
    var outcome: LoadOutcome
    var warnings: [LoadWarning]               // показываются в настройках/onboarding, не модально
    var brokenFileURL: URL?                   // если исходный файл был переложен в broken/
}

enum SaveError: Error, Equatable {
    case readOnlyFutureVersion, diskFull, permissionDenied, encodeFailed, ioFailed(String)
}

final class SettingsStore {
    init(directory: URL, legacyDefaults: UserDefaults, clock: @escaping () -> Date = Date.init)

    /// Синхронно, на main, до создания UI. Никогда не бросает: худший случай — дефолт + причина в outcome.
    func load() -> LoadResult

    /// Запланировать запись. Дебаунс 0.5 с. Равный последнему записанному снимок не пишется.
    func scheduleSave(_ snapshot: SettingsSnapshot)

    /// Немедленная запись ожидающего снимка. Вызывать из applicationWillTerminate,
    /// NSWorkspace.willSleepNotification и при закрытии окна настроек. Ждёт не дольше 2 с.
    @discardableResult func flush() -> Result<Void, SaveError>

    /// Публикуется на main. nil — последняя запись успешна.
    var lastSaveError: SaveError? { get }
    var onSaveErrorChange: ((SaveError?) -> Void)?

    var isReadOnly: Bool { get }              // true при futureVersion

    // Резервные копии
    func backups() -> [BackupInfo]            // дата, тип, размер, schemaVersion
    func restore(_ backup: BackupInfo) throws -> SettingsSnapshot   // сначала делает pre-import копию текущего
    func exportArchive(to url: URL, _ snapshot: SettingsSnapshot) throws
    func previewImport(from url: URL) throws -> ImportPreview       // ничего не применяет
}

struct ImportPreview {
    var snapshot: SettingsSnapshot
    var warnings: [LoadWarning]
    var summary: (spaces: Int, items: Int, profiles: Int)
}
```

**Потоки.** `load()` — синхронно на main при старте. Кодирование снимка — на main (это быстро:
десятки КБ). Запись на диск — на последовательной очереди `settings.io`. Колбэки — на main.
Владелец таймера дебаунса — `SettingsStore`; `flush()` отменяет таймер.

**Запись атомарно:** `JSONEncoder` (`.sortedKeys`, `.prettyPrinted`) → временный файл в том же каталоге →
`FileHandle.synchronize()` → `FileManager.replaceItemAt` → проверка чтением (декод того, что записано) →
только после этого снимок считается записанным. При ошибке прежний `settings.json` не тронут.

**Резервные копии:** `settings-*.json` — не чаще раза в 30 минут при изменениях, хранить 10 последних;
`pre-migration-*` — перед каждой миграцией, без ротации; `pre-import-*` — перед импортом и восстановлением,
5 последних.

**Будущая версия.** `schemaVersion > currentSchema` → файл не перезаписывается, `isReadOnly = true`,
панель работает на прочитанных данных, насколько это возможно. Пользователю показывается: «Настройки созданы более новой
версией. Открой её или восстанови резервную копию». Действия: «Восстановить копию…», «Продолжить без
сохранения».

---

## 6. Алгоритм `load()`

```
1. Есть settings.json?
   нет → есть ли старые ключи 0.5.0 (spaces | pinned | iconSize)?
         да  → миграция v0→v1 (раздел 7) → outcome .migrated(0)
         нет → дефолтный снимок → outcome .fresh
2. Прочитать. Пустой/нечитаемый/не JSON → перенести в broken/, взять самый свежий читаемый backup
   → outcome .recovered; нет backup → миграция из UserDefaults, если ключи есть; иначе .fresh + warning.
3. schemaVersion > current → .futureVersion, read-only.
4. schemaVersion < current → цепочка миграций v(n)→v(n+1), pre-migration копия до первой.
5. normalized() → warnings.
6. Запись после миграции/восстановления — сразу (flush), чтобы следующий старт был .loaded.
```

Каждый шаг покрывается тестом (раздел 8).

---

## 7. Миграция v0 (UserDefaults 0.5.0) → v1

1. Снять **полный** дамп домена `app.newmacbar.desktop` (`persistentDomain(forName:)`) в
   `backups/pre-migration-v0-*.json` (plist → JSON, `Data` → base64). До любых изменений.
2. Пространства: из `spaces` (если есть), иначе одно «Главное» из `pinned`/`quickLinks`/`collections`
   (как делает 0.5.0) + пустые «Работа», «Отдых».
3. Текущее пространство: **верхнеуровневые `pinned/quickLinks/collections` новее**, чем `spaces[selected]`,
   если `save()` 0.5.0 успел записать одно, но не другое. Правило: для выбранного пространства брать
   верхнеуровневые ключи; для остальных — `spaces`.
4. Элементы: `paths` → `ItemRecord(kind: .app)`; `links` → `ItemRecord(kind: .web/.folder/.file)` по
   `QuickLink.kind`; порядок: сначала приложения, затем ссылки (как рисует 0.5.0). Новые UUID.
   **Без проверки существования файлов.**
5. Профили: `DockProfile` → `ProfileRecord` (`spaces = nil`); `ProfileAppearance` optional-поля → дефолты.
5a. Календари: `selectedCalendarIDs == []` → `CalendarSelection.all`; непустой → `.only(Set(ids))`.
    **Иначе после миграции у всех пользователей 0.5.0 пропадут события** (G03 трактует пустой выбор как «ни одного»).
5b. Хоткеи: `launcherEnabled` + `launcherShortcutChoice` + встроенные ⌃⌥1…9, ⌃⌥←/→, ⌃⌥D → `[ShortcutBinding]`.
6. Оформление/поведение/виджеты/календарь/поиск — из ключей таблицы 1.2 с той же нормализацией.
7. `layoutVersion < 2` → применить поправки из `main.swift` (iconSize 36, spacing 8, bottom 4, radius 20,
   magnification 1.35, opacity 0.08) в процессе миграции; после C01 этот код из `main.swift` убирается.
8. `focusSession` и `recentAppPaths` → `runtime.json`.
9. Записать `settings.json`, проверить чтением, затем `settingsStorage = "file-v1"`.
   Старые ключи не удалять.

**Повторная миграция без дублей (DAT-02):** если `settingsStorage == "file-v1"` и `settings.json` есть —
миграция не выполняется. Если маркер есть, а файла нет — восстановление из backup, а не повторная миграция
поверх (чтобы не воскрешать устаревшие данные 0.5.0 молча); если backup нет — миграция из ключей +
предупреждение.

---

## 8. Тесты (идут в C08; до него — как `--self-test` блоки)

| Тест | Сценарий из 12.3 |
|---|---|
| Round-trip: снимок → JSON → снимок, равенство | DAT-01 |
| Миграция фикстуры 0.5.0 (все ключи таблицы 1.2), включая `layoutVersion` 0 и 2 | DAT-02 |
| Повторный запуск после миграции → `.loaded`, без дублей | DAT-02 |
| Пустой файл, мусор, обрезанный JSON, `schemaVersion = 99` | DAT-03 |
| Сбой записи (каталог только для чтения, подменённый `FileManager`) → прежний файл цел, `lastSaveError` | DAT-03 |
| «Авария» между временным файлом и заменой → при старте читается прежний `settings.json` | DAT-03 |
| Пути на несуществующем томе `/Volumes/NoSuchDisk/X.app` переживают load → save → load | DAT-04 |
| Дубли ID, 31+ пространство, повторяющийся `desktop`, неизвестный enum | DAT-06 |
| `flush()` при выходе пишет последний снимок; в idle 5 минут — 0 записей | 12.1 «Хранение» |
| Импорт настроек не трогает `systemDockBackup` | контракт X01 |
| `selectedCalendarIDs = []` из 0.5.0 → `.all`, события видны; `.only([])` → состояние «не выбран ни один» | CAL-01 |
| Профиль с `spaces = nil` применяется без изменения пространств | SPC-02 |

Тестовые данные — во временном каталоге и отдельном `UserDefaults(suiteName:)`, никогда в реальном домене.

---

## 9. Вопросы к владельцу и Codex

| ID | Вопрос | Предложение по умолчанию |
|---|---|---|
| Q1 | Исправить D1 (потеря элементов на отключённом диске) отдельным мини-фиксом **до** C01? Это 3 места в Model/Spaces/Actions: убрать фильтр по существованию из пути «загрузка → сохранение», оставить только при отрисовке. | Да, задача `C00-hotfix`, Claude пишет, Codex проверяет на Mac. Это S0. |
| Q2 | Что делать с пространствами сверх лимита 30? | Не удалять; показывать в настройках с пометкой и запретом создавать новые, пока не станет ≤ 30. |
| Q3 | Коллекции в v1: ссылаться на `ItemRecord.id` или хранить пути, как сейчас? | v1 — пути (меньше риск миграции); ссылки — в C02, если понадобятся для undo. |
| Q4 | Security-scoped bookmarks для файлов/папок (переживают переименование и переезд)? | Поле зарезервировать, заполнять после 1.0 — приложение не в песочнице, пути работают. |
| Q5 | Удалять ли старые ключи UserDefaults после миграции? | Нет в 1.0 (откат на 0.5.0). Удаление — после 1.0. |
| Q6 | Codex: допустим ли синхронный `load()` на main до показа панели (оценка ≤ 20 мс на 30 пространств × 500 элементов)? | Да; если нет — асинхронная загрузка с пустой панелью-заглушкой. |
| Q7 | Codex: где вызывать `flush()` — `applicationWillTerminate`, `willSleep`, закрытие настроек. Что-то ещё (выход из профиля пользователя)? | `NSWorkspace.willPowerOffNotification` тоже. |
| Q8 | Gemini/владелец: `CalendarSelection` вместо пустого массива (см. 5a) — подтвердить. | Да. |
| Q9 | Владелец: профиль хранит **все** пространства (G01) или только текущий набор (0.5.0)? | Опционально: галочка «Включить пространства» при сохранении и при импорте. |

---

## 10. Разбиение на подзадачи (после P01)

| ID | Результат | Файлы (владение Claude по 5.2) | Проверка |
|---|---|---|---|
| C01a | Типы `SettingsSnapshot` v1, enum-ы, `SettingsLimits`, декодирование с дефолтами, `normalized()` | новые `Settings/*.swift` | round-trip, DAT-06 |
| C01b | `SettingsStore`: атомарная запись, дебаунс, `flush`, backups, `load()` с восстановлением | `Settings/SettingsStore.swift` | DAT-01, DAT-03 |
| C01c | Миграция v0→v1 и подключение к `BarModel` как фасаду (`init` из `LoadResult`, `save()` → `scheduleSave`) | `Model.swift`, `Spaces.swift`, `Actions.swift` (модельная часть) | DAT-02, DAT-04 |
| C01d | Экспорт полного архива, предпросмотр импорта, восстановление из копии (UI — Codex) | `Settings/SettingsArchive.swift` | DAT-05 |

У каждой подзадачи — своя ветка `claude/C01x-…` и своя проверка на Mac у Codex.

---

## 11. Сверка с дизайном Gemini (v2)

| Документ Gemini | Что требует от хранения | Решение в C01 v2 |
|---|---|---|
| G01 §3, G01 §5 «Система» | профиль может включать список пространств | `ProfileRecord.spaces: [SpaceRecord]?` (Q9) |
| G01 §5 «О программе» | показать версию схемы данных | `SettingsSnapshot.schemaVersion` + `SettingsStore.backups()` |
| G01 §5 «Система» | список автоматических бэкапов и восстановление | `backups()`, `restore(_:)` — раздел 5 |
| G01 §4 сц. 6, G03 3.6 | недоступная папка не удаляется, ярлык «как есть» | D1 + «существование не проверяется никогда» (4.2) |
| G01 §5 «Приложения» | лимиты коллекций 50 / 200 | `SettingsLimits` (раздел 4) |
| G01 §5 «Приложения» | недавние приложения в настройках | `runtime.json` → `RuntimeState.recentApps` (только чтение для UI) |
| G02 §5, G01 §5 «Клавиши» | редактируемые сочетания (`HotkeyRecorder`) | `SettingsSnapshot.shortcuts` (C07) |
| G03 3.2 | «не выбран ни один календарь» — отдельное состояние | `CalendarSelection` (Q8, миграция 5a) |
| design_tokens.json | ID тем и акцентов | rawValue enum-ов не меняются |
