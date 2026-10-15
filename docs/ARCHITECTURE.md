# Architecture and service contracts

[English](ARCHITECTURE.md) | [Russian](ARCHITECTURE.ru.md)

## State ownership

`BarModel` is the source of panel state. Related mutations run inside `batch` so
observers receive one coherent update. A `BarSpace` owns app paths, links, collections
and an optional desktop binding. Before switching spaces, the current snapshot is
saved. Removing or reordering spaces must leave a valid selected ID.

Profiles store appearance plus a snapshot of the current panel. Calendar connections
are global and are not overwritten by profile application. New Codable fields are
optional or decode with defaults. Numeric and enum preferences are normalized through
`SettingsRules`; unsupported or missing files do not erase a saved app shortcut.

Preferences use the application's stable local UserDefaults domain. UI-only state
belongs to `UIStateStore`. Session ownership and the system Dock recovery backup are
separate from exportable panel profiles. Import is bounded and validated before use;
export contains the selected local profile, not recovery or session data.

The current implementation does not claim an atomic, versioned document-store
backend. Such a change requires a migration contract and round-trip tests before
replacing existing storage.

## Runtime and windows

`AppDelegate` coordinates services, menus and popovers. `DockWindowController` owns a
nonactivating AppKit panel. `PanelPlacement` handles display identity and geometry;
`PanelContentLayout` shares a sizing decision between drawing, hit testing and accessibility.
Transparent margins pass clicks through at the window level.

`DockVisibilityPolicy` is a pure state machine. Auto-hide starts hidden, uses edge
dwell and a leave delay, and rejects activation or ordinary clicks as reveal triggers.
Popovers can retain an already visible panel. Overview and wake transitions cannot
leave stale presentation permission behind.

The system Dock is changed only after replacement is enabled. Its three visibility
preferences are backed up before mutation. The backup is validated, retained after
failed recovery and restored on normal exit. The pinned app arrays are read only.
Mission Control remains system-owned; the custom panel yields there to avoid overlap.

## Service boundaries

| Component | Responsibility |
|---|---|
| `AppCatalog` | Local app discovery and search ranking |
| `CalendarController` | Permission-gated event reads and stale-response rejection |
| `MusicController` | Player selection, explicit Automation access and playback data |
| `FocusTimer` | Persisted focus session and planned duration |
| `FolderPresentationLoader` | Asynchronous bounded directory reads and obsolete request rejection |
| `BadgePoller` | Optional Accessibility reads off the main thread |
| `SessionLifecycle` | Single writer, kernel lock and coordinated Dock recovery |
| `PanelActions` | Validated presentation commands and scoped layout undo |
| `Localization` | Catalog lookup, interpolation, plural forms and language changes |

UI state publication belongs on the main thread. Background requests capture a
generation and ignore obsolete results. New asynchronous services must provide
cancellation, weak owner references and teardown for timers and observers.

Permissions are requested by a user action only. Services must not request them on
startup or polling. Native context menus are created when clicked. Destructive file
actions remain explicit and separate from shortcut removal.

## Source layout

All Swift code is under `Sources/Panopticon`. Shared visual tokens are implemented
in `DesignSystem.swift`, `Theme.swift` and `PanelPalette.swift`; the matching design
reference is `design/design_tokens.json`. Localization catalogs are bundled from
`Sources/Panopticon/Resources`. Build metadata comes from `resources/Info.plist`.

Implementation history and contributed planning documents remain in Git. This
reference describes the running interfaces rather than promising unimplemented APIs.
