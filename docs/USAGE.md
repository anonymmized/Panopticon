# User guide

[English](USAGE.md) | [Russian](USAGE.ru.md)

## Install and update

Download the DMG from the [latest release](https://github.com/anonymmized/Panopticon/releases/latest),
open it and drag Panopticon into Applications. Requires macOS 13+; one app supports
Apple Silicon and Intel. Quit the running copy before updating. Preferences are preserved.
No source build is required for normal installation. If macOS blocks the first launch,
try opening it, then use System Settings > Privacy & Security > Open Anyway and confirm.
This build is not notarized by Apple. No automatic in-app updater is included.

## Choose an open window

Hover over a running app for about half a second. The list shows up to 30 available
windows; scroll if needed. Click a window to switch to it or restore it from the Dock.
The app context menu also offers **Application windows…**. Hovering never takes
keyboard focus from your current app.

Enable Accessibility with the explicit button if needed. Revoke it at any time in
macOS Settings. Turn window selection off in **Behavior & displays > Windows on hover**.
Titles are queried only for the selected app; Screen Recording permission is not needed.
Individual browser tabs remain inside the browser. If a window closes or the app
stops responding, refresh the list or open the app.

## Apps and spaces

Open Settings from the menu-bar icon or the panel context menu. Import apps from the
macOS Dock or add application bundles yourself. Closing a pinned app leaves its icon
on the panel. Temporary running apps disappear when they quit; choose **Keep in Dock**
to keep them. Unpinning removes a shortcut, never the application on disk.

Drag icons to reorder them. Drop an item onto a space symbol to move it to that space.
Each space owns its apps, collections, folders and websites. Appearance and calendar
connections are shared. Desktop bindings can follow the active macOS desktop when
its number is available; manual switching always remains available.

## Visibility and displays

Choose an edge and display in **Behavior & displays**. Follow cursor moves the panel
between displays. If a saved display is disconnected, the panel uses an available
display and keeps your choice for reconnection.

Auto-hide begins hidden. Hover briefly at the selected edge to reveal it. Moving away
hides it after a short delay. A deliberate file drag can reveal the panel for dropping.
Settings and unrelated clicks do not summon a hidden panel. Explicit menu and keyboard
actions can reveal it.

Full animations enables the magnification wave and launch bounce. Follow macOS respects
Reduce Motion. Reduced mode keeps feedback without icon enlargement or bouncing.
Reduce Transparency uses opaque surfaces; Increase Contrast strengthens borders.

## Widgets

Choose up to two different widgets in Settings. Vertical panels use compact widgets
so their content stays readable. A focus session survives restarts. Changing the next
session duration preserves a paused session; Reset explicitly starts over.

Choose Spotify, Apple Music or automatic player selection. Click to connect control
when needed. Browser playback is not supported. Track names and artwork come from the
selected player and are never translated.

Calendar click actions can open any app bundle or an http/https calendar website.
Event access is separate: connect macOS calendars and choose which to display.
An empty saved selection means all calendars; **Deselect all** explicitly selects none.
Choosing a third-party calendar app does not import that service's account.

## Folders, files and the Trash

Drop a folder on free panel space to add a stack. Folder stacks support search, grid
or list display, refresh and sorting. Up to 500 items are displayed; Finder can show
the complete folder. A moved or unavailable folder offers retry and Finder access.

Drop a document onto an app icon to open it with that app. Removing a panel shortcut
leaves its original file intact. Dropping a real Finder file onto Trash moves that
file to the system Trash. Empty Trash always asks for confirmation.

## Profiles, search and language

A profile saves appearance and a snapshot of the current layout. Applying a profile
preserves external calendar connections. Import and export use local JSON files.
Review import details before applying; profiles and layout changes offer scoped undo.

Search supports abbreviations and keyboard-layout correction. Arrow keys select,
Return opens, Command-Return pins an app and Escape closes search. The global shortcut
is configurable; the menu-bar entry remains available when a shortcut conflicts.

Interface language is available at the bottom of the settings sidebar. English,
Russian and System apply immediately. Your space names, profile names, paths,
track metadata and event titles stay as entered.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Control-Option-Space | Toggle search; configurable |
| Control-Option-1 through 9 | Select a space |
| Control-Option-Left / Right | Previous / next space |
| Control-Option-D | Show / hide panel |
| Command-comma | Settings while the app is active |

## Recovery

Use **Restore system Dock** in the menu bar or System & recovery. After an interrupted
session, Panopticon preserves the backup and lets you restore or continue. The CLI
`Panopticon --restore-system-dock` coordinates with a running instance; it does not
race a second writer against that instance.

For the full edge slide, choose **Appearance > Motion > Full animations**. Follow macOS
respects the system Reduce Motion setting; reduced mode uses a brief fade instead.
Apps receive their normal reopen request even when already running, so each app can
restore or create its window when it has no open windows.

After updating an ad-hoc signed build, macOS may require approving Accessibility
or other connections again. The panel preferences themselves are preserved.
