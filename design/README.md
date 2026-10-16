# Design system

[English](README.md) | [Russian](README.ru.md)

Panopticon follows native macOS materials, familiar app icons and restrained motion.
Reliability and readable controls take priority over decorative effects. The machine
reference is [design_tokens.json](design_tokens.json); runtime palettes are implemented
in `PanelPalette.swift`, and shared interface styling lives in `DesignSystem.swift`.

## Surfaces and type

Eight persistent theme identifiers are supported: Glass, Dark, Light, Aurora, Electric,
Sunset, Graphite and Frost. Glass follows system appearance. Light and Frost use light
materials; the remaining colored themes use dark materials. Settings and popovers
follow their separately selected system, light or dark appearance.

Panel borders and the inner rim come from semantic theme colors. Widget text uses
a protective background before the accent wash so wallpaper does not dominate it.
Reduce Transparency switches to an opaque fallback; Increase Contrast strengthens
boundaries. Graphite uses a brighter accent for legibility.

System fonts are used throughout. Shared window headings are 20 pt, section headings
15 pt, body text 13 pt and captions 11 pt. Direct panel controls avoid sub-10 pt fonts.
Text should wrap or truncate intentionally; never shrink arbitrary labels to fit.
No universal contrast certification is claimed for every wallpaper and user setting.

## Motion and input

Magnification uses a neighbor wave with frame-rate-independent springs. Launch feedback
uses a short bounce; reduced motion keeps an opacity response. Hover enlargement and
press feedback stay within the panel's interactive bounds. Idle animations settle
and stop their timers.

The panel does not take keyboard focus. Transparent margins pass through clicks.
Text-entry popovers and search can become key. Context menus are native and built at
click time. Escape closes search; scoped undo must not capture another editor's work.

App shortcuts and real files have distinct drag semantics. Shortcut removal never
deletes the original. Moving real files to Trash remains explicit. Cross-space moves,
reordering and overflow access must keep stable identity and readable hit targets.

## Information and states

Settings use a searchable sidebar with appearance, spaces, apps, collections, widgets,
connections, profiles, behavior, keyboard, recovery and about sections. The minimum
window is 760 by 540 pt; scrolling keeps controls accessible.

Calendar access, selected sources and the app used for opening are separate concepts.
Folder loading, empty, filtered and unavailable states have distinct messages.
Player access is requested only on an explicit action. Destructive actions name what
is removed and explain whether original files are affected.

Use complete English and Russian catalogs. Do not expose technical preference keys,
raw color identifiers or unimplemented features as product controls. Keep user names,
file names and event metadata unchanged when switching language.

The system Mission Control Dock is outside the custom panel's supported replacement
surface. Avoid duplicate bars and describe this boundary honestly.

## Reveal and window list

The panel slides from the selected edge over a short eased transition. Reversing
starts at the currently displayed frame. Reduce Motion uses a short opacity change.
There is no permanent display timer at rest. The window list appears after a deliberate
hover, uses native material, readable two-line rows and a minimized-window indicator,
and leaves keyboard focus in the current app. It stays within the selected display.
A brief pointer-transit allowance connects the app icon to the list without flicker.
