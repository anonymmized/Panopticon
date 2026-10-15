# Черновики контрактов логики → Codex (C01–C07), v2

**Статус:** черновик v2, волна 0. Не реализовано. Названия — проектируемые интерфейсы, а не существующие методы.
**База:** `main` @ `53dd4a3`. **Сверено с:** `design/` G01, G02, G03/G04, `design_tokens.json` (ветка `design`).
**Ревью:** Codex (потребитель), Gemini (состояния экранов).
Контракт C01 подробно — в [C01-STORAGE.md](C01-STORAGE.md).

**Что изменилось в v2 (по дизайну Gemini):**
C02 — дублирование пространства, копирование по ⌥, снятие закрепления из поиска;
C03 — «не выбран ни один календарь», точки дней месяца, ближайшее событие;
C04 — альбом, shuffle/repeat, «доступ не запрошен» отдельно от «отказ», удержание seek, пресеты таймера;
C05 — типы результатов как в G03, ⌘↵ закрепляет **или** снимает закрепление;
C06 — фильтр по имени, лимит 100, сортировка «по дате», действия для недоступной папки;
C07 — хоткей таймера, проверка сочетания до применения, сброс к стандартным.
Открытые вопросы — раздел «Сверка с дизайном» в конце.

## Общие правила для всех сервисов

1. **Публикация состояния — только на main thread.** Сервис — `ObservableObject` с одним
   `@Published private(set) var state: XState` (значение, `Equatable`). UI не читает внутренние поля сервиса.
2. **Команды** — методы сервиса; ничего не возвращают синхронно, кроме явной валидации.
   Результат приходит через `state`.
3. **Поколения.** Каждый асинхронный запрос несёт `generation: UInt64`. Ответ с устаревшим поколением
   отбрасывается. Так закрываются гонки «старый ответ перезаписал новую команду».
4. **Владелец таймеров и наблюдателей** — сам сервис. `deinit` и `stop()` освобождают всё.
   Сервис с `isEnabled == false` не имеет ни одного активного таймера, запроса или наблюдателя.
5. **Разрешения запрашиваются только методом с суффиксом `…ByUser()`**, который UI вызывает
   из обработчика нажатия. Фоновые методы никогда не показывают системный диалог.
6. **Ошибки** — enum с понятной пользователю причиной и, где возможно, следующим шагом
   (`recovery: RecoveryAction?` — `.openSystemSettings(pane)`, `.relink`, `.retry`, `.launchApp(bundleID)`).
   Никаких `NSAlert` из сервисов: показывает UI.
7. **Зависимости внедряются** (часы, файловая система, исполнитель AppleScript, EventStore),
   чтобы C08 мог тестировать без разрешений и реальных данных.
8. **Тексты** сервисы не формируют. Они отдают состояние, а строки берутся из каталога G04 (`calendar.empty.no_access`
   и т.п., задача C09). Исключение — сообщения ошибок ОС, которые передаются как есть в поле `detail`.

---

## C02 — `AppCommand` / `MutationResult`

```swift
enum AppCommand: Equatable {
    case addItems([NewItem], space: SpaceID, at: Int?)          // drop, «+», поиск ⌘↵
    case removeItem(ItemID, space: SpaceID)                     // ярлык, не файл (DRG-03)
    case moveItem(ItemID, from: SpaceID, to: SpaceID, at: Int?) // drop на кнопку пространства
    case copyItem(ItemID, to: SpaceID)                          // тот же drop с зажатым ⌥ (G03 §2)
    case reorderItem(ItemID, space: SpaceID, to: Int)
    case renameItem(ItemID, name: String?)
    case relinkItem(ItemID, location: String)                   // «Указать новый путь/папку…» (G01 §5, G03 3.6)
    case addSpace(name: String, symbol: String)
    case duplicateSpace(SpaceID)                                // G01 §5 «Пространства»
    case removeSpace(SpaceID)                                   // последний удалить нельзя
    case renameSpace(SpaceID, name: String)
    case setSpaceSymbol(SpaceID, symbol: String)
    case reorderSpace(SpaceID, to: Int)
    case bindSpace(SpaceID, desktop: Int?)
    case selectSpace(SpaceID)
    case saveProfile(name: String, includeSpaces: Bool)
    case applyProfile(ProfileID, includeSpaces: Bool)
    case deleteProfile(ProfileID)
    case importArchive(ImportPreview, mode: ImportMode)         // .add | .replace | (отмена = не вызывать)
}

struct MutationResult: Equatable {
    var applied: Bool
    var changedSpaceIDs: [SpaceID]
    var undo: UndoDescription?        // nil — необратимо (импорт .replace — откат через backup C01)
    var skipped: [SkippedItem]        // дубль, неподдерживаемый тип, лимит — с причиной
    var highlightItemID: ItemID?      // дубль при drop: подсветить существующий элемент импульсом (DRG-05, G03 §2)
    var error: CommandError?
}
enum CommandError: Equatable { case notFound, lastSpace, limitReached(Int), invalidName, invalidLocation, readOnlyStorage }

final class AppCommands {   // фасад над BarModel
    @discardableResult func perform(_ command: AppCommand) -> MutationResult
    func undo() -> MutationResult?   // ⌘Z в настройках и после тоста «Убрано с панели»
    var canUndo: Bool { get }
    var undoTitle: UndoDescription? { get }
}
```

- Одно логическое действие — один `perform` — одно изменение снимка — одна запланированная запись.
- `selectSpace` никогда не меняет `calendar`, `launcher`, разрешения, автозапуск, Dock-backup (инвариант 2, G01 §3).
- Стек отмены — 20 шагов, только в памяти, очищается при импорте/восстановлении.
- `ItemAvailability` (`.available | .missing | .volumeOffline(name)`) вычисляется для отрисовки
  (янтарный бейдж G01 сц. 6, `accessibilityLabel` «путь временно недоступен» G03 §4.1), **не хранится**.
- Drop за пределы панели (> 48 pt) и drop на Корзину для **внутреннего** элемента — одна и та же команда `removeItem`.

| Состояние | Пример |
|---|---|
| Пусто | `removeItem` по несуществующему id → `applied: false, error: .notFound` |
| Обычное | drop двух файлов, один уже есть → `applied: true, skipped: [дубль], highlightItemID: <старый>` |
| Ошибка | `removeSpace` последнего → `applied: false, error: .lastSpace` |

---

## C03 — `CalendarState` / `CalendarActions`

```swift
struct CalendarState: Equatable {
    var access: CalendarAccess        // .notDetermined | .granted | .denied | .restricted | .error(detail: String)
    var isEnabled: Bool               // calendarEventsEnabled; выключено → нет запросов
    var selection: CalendarSelection  // .all | .only(Set<String>) — C01 v2
    var availableCalendars: [CalendarInfo]     // id, title, colorHex, sourceTitle
    var month: DateComponents                  // год+месяц отображаемого месяца
    var dayMarkers: [Int: [String]]            // день месяца → до 3 colorHex для точек под числом (G03 3.2)
    var selectedDay: Date
    var dayEvents: Loadable<[AgendaEvent]>
    var nextEvent: AgendaEvent?                // для виджета на панели (G01 сц. 4); nil = «Свободно»
    var sourceSummary: SourceSummary           // для футера: число выбранных календарей
}
enum Loadable<T: Equatable>: Equatable { case idle, loading, loaded(T), failed(detail: String) }

protocol CalendarActions {
    func connectByUser()                       // «Разрешить доступ» — единственный путь к системному диалогу
    func showMonth(_ month: DateComponents)    // ‹ › Сегодня; отменяет предыдущий запрос
    func selectDay(_ day: Date)
    func setSelection(_ selection: CalendarSelection)
    func setEnabled(_ on: Bool)
}
```

**Состояния поповера (ровно как G03 3.2):**

| Экран G03 | Условие в `CalendarState` | `recovery` |
|---|---|---|
| 1. «Подключите Календарь macOS» | `access == .notDetermined` | кнопка → `connectByUser()` |
| 2. «Нет доступа к Календарю» | `access == .denied \|\| .restricted` | `.openSystemSettings(.calendars)` |
| 3. «Не выбран ни один календарь» | `access == .granted`, `selection == .only([])` **или** все выбранные календари удалены | открыть настройки «Связи» |
| 4. «На этот день встреч нет» | `dayEvents == .loaded([])` | — |

- События читаются на фоновой очереди, публикуются на main с проверкой поколения.
- Пересчёт по `EKEventStoreChanged`, `NSCalendarDayChanged`, `NSSystemTimeZoneDidChange`, пробуждению.
- Многодневное событие даёт маркер на каждый свой день месяца. Повторяющиеся — как отдельные вхождения.
- Назначение открытия (`calendarDestination`) — не часть этого сервиса (CAL-03); в футер оно приходит из настроек.

---

## C04 — `PlayerState` / `PlayerActions` и `FocusState`

```swift
struct PlayerState: Equatable {
    var source: PlayerSource?             // .spotify | .music | nil = не запущен
    var availability: PlayerAvailability
    var track: TrackInfo?                 // title, artist, album, duration, artworkURL
    var isPlaying: Bool
    var position: Double                  // на момент sampledAt
    var sampledAt: Date
    var isSeeking: Bool                   // G03 3.3: пока true, ответы плеера не двигают ползунок
    var volume: Double                    // 0...100
    var shuffle: Bool?                    // nil — источник не сообщает
    var repeatMode: RepeatMode?           // .off | .one | .all; nil — не поддерживается
}
enum PlayerAvailability: Equatable {
    case noPlayerRunning                  // «Плеер сейчас не запущен» + «Запустить …»
    case permissionNotRequested           // «Подключить управление плеером»
    case permissionDenied                 // «Разрешите управление … → Автоматизация»
    case noTrack, ready
    case temporaryError(detail: String)
}
protocol PlayerActions {
    func playPause()
    func next()
    func previous()
    func beginSeek()                      // UI начал тянуть ползунок
    func commitSeek(to seconds: Double)   // отпустил; ответ старше команды игнорируется
    func setVolume(_ value: Double)
    func setShuffle(_ on: Bool)
    func setRepeat(_ mode: RepeatMode)
    func requestAccessByUser()            // Automation-диалог только отсюда
    func launchPlayer()                   // «Запустить Spotify / Apple Music»
    func setPreference(_ p: PlayerPreference)   // .auto | .spotify | .music
    func setVisible(_ visible: Bool)      // политика опроса: виджет 2 с, поповер 1 с, скрыт — 0
}

struct FocusState: Equatable {
    var phase: FocusPhase                 // .ready | .running(endsAt: Date) | .paused(remaining: Double) | .finished
    var sessionDuration: Double           // текущей/последней сессии
    var nextDuration: Double              // пресеты 15/25/45/60 и степпер 5…90 (G03 3.4)
    var nextDurationPending: Bool         // true → подпись «Применится к следующей сессии»
}
protocol FocusActions {
    func startOrPause()
    func reset()
    func setNextDuration(minutes: Int)
}
```

- «Доступ не запрошен» и «отказ» различаются без диалога: `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)`
  → `errAEEventWouldRequireUserConsent` (−1744) = не запрошен, `errAEEventNotPermitted` (−1743) = отказ.
- Опрос AppleScript — на последовательной очереди с таймаутом 1,5 с. Backoff 2→4→8→30 с при ошибках.
- Таймер хранит `endsAt`; после сна/перезапуска пересчитывает. `finished` наступает и звучит один раз
  (флаг в `runtime.json`). Строки «Фокус идёт / На паузе / Готов к старту» — по `phase`.

---

## C05 — `SearchQuery` / `SearchResult`

```swift
struct SearchQuery: Equatable { var text: String; var scope: SearchScope = .all; var id: UInt64 }
struct SearchResult: Identifiable, Equatable {
    var id: String              // стабильный: "app:<path>", "item:<uuid>", "space:<id>", "collection:<id>", "profile:<id>", "action:<name>"
    var kind: ResultKind        // .app | .space | .collection | .link | .folder | .profile | .command  (бейджи G03 3.5)
    var title: String
    var context: ResultContext  // .space(name) | .path(String) | .none — «В пространстве: Работа»
    var iconRef: IconRef        // путь/URL/символ — без NSImage (иконку грузит C06)
    var score: Int
    var pinAction: PinAction    // .pin | .unpin(ItemID) | .unavailable — для ⌘↵
}
final class SearchEngine {
    func search(_ q: SearchQuery) -> [SearchResult]      // синхронно по индексу, ≤ 100 мс p95 (12.1)
    func rebuildIndex(from snapshot: SettingsSnapshot, apps: [URL])   // фон, атомарная замена индекса
    func recordLaunch(_ id: String)                       // локальная история для ранжирования
}
```

- **Стабильный выбор (SRC-02, G03 3.5):** UI хранит `selectedResultID`. При асинхронном обновлении выдачи
  выбор не двигается, пока пользователь сам не нажал ↑/↓ или не изменил текст. Если выбранного ID больше
  нет — выбор переходит на первый результат, и Enter не срабатывает 150 мс.
- Enter → открыть/выполнить; ⌘Enter → `pinAction` (закрепить **или** убрать), никогда не запускает приложение.
- Движок не создаёт `NSImage` и не делает I/O на каждый символ. Понимает неверную раскладку и инициалы.

---

## C06 — `FolderState` / `IconState`

```swift
struct FolderState: Equatable {
    var location: String
    var status: FolderStatus     // .loading | .loaded | .empty | .unavailable(reason) | .noAccess | .failed(detail)
    var entries: [FolderEntry]   // name, path, isDirectory, isPackage, dateModified, dateAdded
    var filterText: String       // «Фильтр файлов…» (G03 3.6) — фильтрует сервис, не View
    var sort: FolderSort         // .name | .date (Q-G5: дата изменения или добавления)
    var shownCount: Int          // ≤ limit
    var totalCount: Int          // для «Показаны первые 100 из 640 объектов»
    var limit: Int               // 100 по G01/G03
}
enum UnavailableReason: Equatable { case volumeOffline(name: String), moved, deleted }

final class FolderService {
    func open(_ location: String, sort: FolderSort) -> FolderHandle   // handle.cancel() при закрытии поповера
    // handle.setFilter(_:), handle.setSort(_:), handle.refresh()
}
final class IconService {
    func icon(for ref: IconRef, size: CGFloat) -> NSImage?            // кеш, nil = ещё грузится
    var onIconsChanged: (() -> Void)?
}
```

- Чтение папки — фон, выдача порциями по 50, отмена через `FolderHandle` (кнопка «Отменить» в скелетоне G03).
- `.unavailable` → действия «Указать новую папку…» (`AppCommand.relinkItem`) и «Оставить ярлык как есть» (ничего).
- Сайты: только сам сайт (`/apple-touch-icon.png`, `/favicon.ico`), таймаут 5 с, ≤ 3 редиректа,
  ≤ 1 МБ, проверка размера во время загрузки, кеш до 200 записей / 20 МБ, повтор ошибки не чаще раза в сутки.

---

## C07 — `ShortcutBinding` / `ShortcutStatus`

```swift
struct ShortcutBinding: Codable, Equatable {
    var id: ShortcutID          // .launcher, .toggleBar, .space(1...9), .previousSpace, .nextSpace, .focusToggle
    var keyCode: UInt32?        // nil = выключено
    var modifiers: UInt32
}
enum ShortcutStatus: Equatable { case active, disabled, conflict, failed(OSStatus) }   // «✓ Подключено», «✕ Выключено», «⚠ Конфликт», «Ошибка»

final class ShortcutRegistry {
    func apply(_ bindings: [ShortcutBinding])           // перерегистрирует только изменённые
    func check(_ binding: ShortcutBinding) -> ShortcutStatus   // для HotkeyRecorder до сохранения (G02 §5)
    static var defaults: [ShortcutBinding] { get }      // «Сбросить сочетания»
    var status: [ShortcutID: ShortcutStatus] { get }    // @Published
    var onTrigger: ((ShortcutID) -> Void)?              // одно нажатие → один вызов, на main
}
```

- Единственное место `RegisterEventHotKey` в приложении. `HotKeys` и `GlobalShortcut` сливаются сюда.
- Повтор при удержании клавиши (`kEventHotKeyPressed` повторно < 300 мс) гасится.
- Пространства не вызывают launcher; launcher не переключает пространство (KEY-01).
- Конфликт внутри приложения (два действия на одно сочетание) ловится `check` до регистрации; конфликт
  с другой программой — по ошибке `RegisterEventHotKey`.

---

## Сверка с дизайном Gemini (v2)

### Принято в контракты

| Где у Gemini | Что | Куда |
|---|---|---|
| G03 §2 | ⌥ при drop на пространство = копировать | C02 `copyItem` |
| G03 §2 | дубль при drop подсвечивается импульсом | C02 `highlightItemID` |
| G01 §5 | дублирование пространства | C02 `duplicateSpace` |
| G01 §3 | профиль может включать пространства | C02 `includeSpaces`, C01 `ProfileRecord.spaces` |
| G03 3.2 | 4 состояния календаря, точки дней | C03 таблица состояний, `dayMarkers` |
| G01 сц. 4 | ближайшее событие на панели / «Свободно» | C03 `nextEvent` |
| G03 3.3 | seeking, shuffle, repeat, альбом, 3 состояния доступа | C04 |
| G03 3.4 | пресеты и «применится к следующей сессии» | C04 `FocusState` |
| G03 3.5 | бейджи типов, `selectedResultID`, ⌘↵ = закрепить/убрать | C05 |
| G03 3.6 | фильтр, лимит 100, «Указать новую папку…» | C06 |
| G01 §5, G02 §5 | хоткей таймера, статусы, `HotkeyRecorder` | C07 |

### Нужно решение (Gemini / владелец)

| ID | Вопрос | Предложение |
|---|---|---|
| Q-G1 | В 0.5.0 пустой выбор календарей = «все», в G03 — «ни одного». | `CalendarSelection.all / .only(...)`; миграция `[] → .all`. Иначе у всех пропадут события. |
| Q-G2 | G01 §5 «Связи» перечисляет `playerPreference: … web`. В 0.5.0 такого значения нет, README 0.5.0: «Музыка из браузера не поддерживается». Это расширение объёма 1.0 (план §3.4 — решает владелец). | Убрать `web` из макета до 1.0. |
| Q-G3 | G01 сц. 3 упоминает хоткеи `Ctrl+1`, `Ctrl+2`; в 0.5.0 — ⌃⌥1…9. В macOS ⌃1…⌃9 — сочетания «Перейти на рабочий стол N» (Mission Control); у кого они включены, будет конфликт. | Оставить ⌃⌥1…9 по умолчанию; пользователь может переназначить в `HotkeyRecorder`. |
| Q-G4 | G03 3.3: кнопки Shuffle/Repeat. Это новое AppleScript-поведение для обоих плееров. | Да, но с `nil`, если источник не сообщает состояние, — кнопка тогда скрыта. |
| Q-G5 | G01: сортировка папки «Дата изменения», G03: «По дате». Dock сортирует «по дате добавления». | `.date` = дата добавления (как Dock), с подсказкой в меню. Решает Gemini. |
| Q-G6 | G03 §2: drop файла на приложение — «если приложение принимает тип файла». | C06 даст `canOpen(fileURL, withApp:)` через `NSWorkspace.urlsForApplications(toOpen:)`; без поддержки типа рамка не показывается. |
