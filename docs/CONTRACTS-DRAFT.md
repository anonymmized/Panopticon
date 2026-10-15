# Черновики контрактов Claude → Codex (C01–C07)

**Статус:** черновик, волна 0. Не реализовано. Названия — проектируемые интерфейсы, а не существующие методы.
**База:** `main` @ `53dd4a3`. **Ревью:** Codex (потребитель), Gemini (состояния для G03).
Контракт C01 подробно — в [C01-STORAGE.md](C01-STORAGE.md).

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
6. **Ошибки** — enum с понятной пользователю локализуемой причиной и, где возможно, следующим шагом
   (`recoveryAction`). Никаких `NSAlert` из сервисов: показывает UI.
7. **Зависимости внедряются** (часы, файловая система, исполнитель AppleScript, EventStore),
   чтобы C08 мог тестировать без разрешений и реальных данных.

---

## C02 — `AppCommand` / `MutationResult`

```swift
enum AppCommand: Equatable {
    case addItems([NewItem], space: SpaceID, at: Int?)          // drop, «+», поиск ⌘↩
    case removeItem(ItemID, space: SpaceID)                     // ярлык, не файл
    case moveItem(ItemID, from: SpaceID, to: SpaceID, at: Int?)
    case copyItem(ItemID, to: SpaceID)                          // только по явному выбору
    case reorderItem(ItemID, space: SpaceID, to: Int)
    case renameItem(ItemID, name: String?)
    case relinkItem(ItemID, location: String)                   // недоступный путь → новый
    case addSpace(name: String, symbol: String)
    case removeSpace(SpaceID)                                   // последний удалить нельзя
    case renameSpace(SpaceID, name: String)
    case reorderSpace(SpaceID, to: Int)
    case bindSpace(SpaceID, desktop: Int?)
    case selectSpace(SpaceID)
    case saveProfile(name: String)
    case applyProfile(ProfileID)
    case deleteProfile(ProfileID)
    case importArchive(ImportPreview, mode: ImportMode)         // .add | .replace
}

struct MutationResult: Equatable {
    var applied: Bool
    var changedSpaceIDs: [SpaceID]
    var undo: UndoDescription?        // nil — необратимо (например, импорт с .replace — через backup)
    var skipped: [SkippedItem]        // дубль, неподдерживаемый тип, лимит — с причиной
    var error: CommandError?
}
enum CommandError: Equatable { case notFound, lastSpace, limitReached(Int), invalidName, invalidLocation, readOnlyStorage }

final class AppCommands {   // фасад над BarModel
    @discardableResult func perform(_ command: AppCommand) -> MutationResult
    func undo() -> MutationResult?
    var canUndo: Bool { get }
    var undoTitle: String? { get }     // «Отменить: удаление Safari»
}
```

- Одно логическое действие — один `perform` — одно изменение снимка — одна запланированная запись.
- `selectSpace` никогда не меняет `calendar`, `launcher`, разрешения (инвариант 2).
- Стек отмены — 20 шагов, только в памяти, очищается при импорте/восстановлении.
- `ItemAvailability` (`.available | .missing | .volumeOffline(name)`) вычисляется для отрисовки, **не хранится**.

| Состояние | Пример |
|---|---|
| Пусто | `perform(.removeItem(x, space: s))` по несуществующему id → `applied: false, error: .notFound` |
| Обычное | drop двух файлов, один уже есть → `applied: true, skipped: [дубль]`, `undo: «Отменить: добавление»` |
| Ошибка | `removeSpace` последнего → `applied: false, error: .lastSpace` |

---

## C03 — `CalendarState` / `CalendarActions`

```swift
struct CalendarState: Equatable {
    var access: CalendarAccess        // .notRequested | .granted | .denied | .restricted | .error(String)
    var isEnabled: Bool               // выключено → нет запросов
    var month: DateComponents         // год+месяц отображаемого месяца
    var selectedDay: Date
    var availableCalendars: [CalendarInfo]     // id, title, colorHex, source
    var selectedCalendarIDs: Set<String>       // пусто = все
    var dayEvents: Loadable<[AgendaEvent]>
    var upcoming: Loadable<[AgendaEvent]>      // ближайшие 7 дней, ≤ 20
}
enum Loadable<T: Equatable>: Equatable { case idle, loading, loaded(T), failed(String) }

protocol CalendarActions {
    func connectByUser()                       // единственный путь к системному диалогу
    func showMonth(_ month: DateComponents)    // отменяет предыдущий запрос
    func selectDay(_ day: Date)
    func setSelectedCalendars(_ ids: Set<String>)
    func setEnabled(_ on: Bool)
}
```

- События читаются на фоновой очереди, публикуются на main с проверкой поколения.
- Пересчёт по `EKEventStoreChanged`, `NSCalendarDayChanged`, `NSSystemTimeZoneDidChange`, пробуждению.
- «Нет доступа», «нет календарей», «нет событий» — три разных состояния: `access != .granted`,
  `availableCalendars.isEmpty`, `.loaded([])`.
- Назначение открытия (`CalendarDestination`) — не часть этого сервиса.

---

## C04 — `PlayerState` / `PlayerActions` и `FocusState`

```swift
struct PlayerState: Equatable {
    var source: PlayerSource?             // .spotify | .music | nil = не запущен
    var availability: PlayerAvailability  // .noPlayer | .noTrack | .ready | .noPermission | .temporaryError
    var track: TrackInfo?                 // title, artist, album, duration, artworkURL
    var isPlaying: Bool
    var position: Double                  // на момент sampledAt
    var sampledAt: Date
    var volume: Double                    // 0...100
}
protocol PlayerActions {
    func playPause()
    func next()
    func previous()
    func seek(to seconds: Double)         // оптимистично обновляет state, ответ старше команды игнорируется
    func setVolume(_ value: Double)
    func requestAccessByUser()            // Automation-диалог только отсюда
    func setPreference(_ p: PlayerPreference)
    func setVisible(_ visible: Bool)      // политика опроса: видим 2 с, скрыт — 0, поповер — 1 с
}

struct FocusState: Equatable {
    var phase: FocusPhase                 // .idle | .running(endsAt: Date) | .paused(remaining: Double) | .finished
    var sessionDuration: Double
    var nextDuration: Double              // изменение длительности не трогает идущую сессию
}
```

- Опрос AppleScript — на последовательной очереди с таймаутом 1,5 с. Backoff 2→4→8→30 с при ошибках.
- `-1743` (нет доступа) → `.noPermission`, опрос прекращается до `requestAccessByUser()`.
- Таймер хранит `endsAt`; после сна/перезапуска пересчитывает. `finished` наступает и звучит один раз
  (флаг в `runtime.json`).

---

## C05 — `SearchQuery` / `SearchResult`

```swift
struct SearchQuery: Equatable { var text: String; var scope: SearchScope = .all; var id: UInt64 }
struct SearchResult: Identifiable, Equatable {
    var id: String                    // стабильный: "app:<path>", "item:<uuid>", "space:<id>", "action:<name>"
    var kind: ResultKind              // .app | .item | .space | .collection | .profile | .action
    var title: String
    var subtitle: String              // контекст: «В наборе „Работа“»
    var iconRef: IconRef              // путь/URL/символ — без NSImage (иконку грузит C06)
    var score: Int
    var canPin: Bool
}
final class SearchEngine {
    func search(_ q: SearchQuery) -> [SearchResult]      // синхронно по индексу, ≤ 100 мс p95 (12.1)
    func rebuildIndex(from snapshot: SettingsSnapshot, apps: [URL])   // фон, атомарная замена индекса
    func recordLaunch(_ id: String)                       // локальная история для ранжирования
}
```

- Стабильный выбор: UI держит выбранный `id`, а не индекс. Если `id` остался в новой выдаче, выделение на нём.
- Enter → открыть, ⌘Enter → закрепить (только `canPin`). Это два разных метода, не флаг.
- Движок не создаёт `NSImage` и не делает I/O на каждый символ.

---

## C06 — `FolderState` / `IconState`

```swift
struct FolderState: Equatable {
    var location: String
    var status: FolderStatus     // .loading | .loaded | .empty | .missing | .volumeOffline | .noAccess | .failed(String)
    var entries: [FolderEntry]   // name, path, isDirectory, dateAdded, isPackage
    var sort: FolderSort         // .name | .dateAdded
    var limit: Int               // 200; если файлов больше — truncatedCount
    var truncatedCount: Int
}
final class FolderService {
    func open(_ location: String, sort: FolderSort) -> FolderHandle   // handle.cancel() при закрытии поповера
}
final class IconService {
    func icon(for ref: IconRef, size: CGFloat) -> NSImage?            // кеш, nil = ещё грузится
    var onIconsChanged: (() -> Void)?
}
```

- Чтение папки — фон, выдача порциями по 50, отмена через `FolderHandle`.
- Сайты: только сам сайт (`/apple-touch-icon.png`, `/favicon.ico`), таймаут 5 с, ≤ 3 редиректа,
  ≤ 1 МБ, проверка размера во время загрузки, кеш до 200 записей / 20 МБ, повтор ошибки не чаще раза в сутки.

---

## C07 — `ShortcutBinding` / `ShortcutStatus`

```swift
struct ShortcutBinding: Codable, Equatable {
    var id: ShortcutID          // .launcher, .toggleBar, .space(1...9), .previousSpace, .nextSpace
    var keyCode: UInt32?        // nil = выключено
    var modifiers: UInt32
}
enum ShortcutStatus: Equatable { case active, disabled, conflict, failed(OSStatus) }

final class ShortcutRegistry {
    func apply(_ bindings: [ShortcutBinding])           // перерегистрирует только изменённые
    var status: [ShortcutID: ShortcutStatus] { get }    // @Published
    var onTrigger: ((ShortcutID) -> Void)?              // одно нажатие → один вызов, на main
}
```

- Единственное место `RegisterEventHotKey` в приложении. `HotKeys` и `GlobalShortcut` сливаются сюда.
- Повтор при удержании клавиши (`kEventHotKeyPressed` повторно < 300 мс) гасится.
- Пространства не вызывают launcher; launcher не переключает пространство (KEY-01).

---

## Что нужно от Codex и Gemini для фиксации контрактов

- **Codex:** подтвердить, что фасад `BarModel` + `AppCommands` не мешает P01; где живут вызовы
  `flush()`; устраивает ли модель `state` + команды для SwiftUI-представлений.
- **Gemini (G03):** перечень состояний для каждого экрана — сверить с enum-ами `Loadable`, `PlayerAvailability`,
  `FolderStatus`, `CalendarAccess`, `ShortcutStatus`. Недостающие состояния добавлю в контракт.
