# Privacy and permissions

[English](PRIVACY.md) | [Russian](PRIVACY.ru.md)

Panopticon has no telemetry, advertising, payment service or required account.
Preferences, paths, layouts, profiles, selected calendars and focus sessions stay
in the application's local preferences domain.

| Permission | Purpose | Requested |
|---|---|---|
| Calendars | Read events from macOS calendar accounts | Connect button |
| Automation for Spotify / Music | Read and control the chosen player | Explicit player action |
| Automation for Finder | Empty the system Trash | After confirmation |
| Accessibility | Optional app window selection and Dock badges | Explicit enable button |

Other features work without these optional connections. Background polling and
startup never request a new permission. macOS manages consent and revocation.
Calendar events are read only; Panopticon does not edit or transmit them.

Spotify artwork is fetched from the address provided by the player. Website icons
are requested directly from sites you add; there is no favicon proxy. Those servers
receive a normal request and the network address of the connection. Local folder
contents are not uploaded.

Diagnostics can be previewed before saving. Reports exclude personal paths, event
contents, website addresses, app lists and display identifiers. Reports are not sent
automatically. JSON profile exports can contain personal paths and names; keep them
out of public source repositories.

System Dock settings are copied before replacement. The backup is local and remains
until recovery succeeds. Normal exit restores those settings. The native pinned app
list is not cleared or rewritten.

Tests use isolated preference suites and generated fixtures. They do not grant
permissions, empty the real Trash or mutate user documents.

## Window selection

Hovering over a running app queries that app's windows through Accessibility.
Titles remain in memory only until the list closes. They are not written to preferences,
diagnostics or telemetry. Other apps' windows are not polled. No screenshots are
captured and Screen Recording permission is never requested. Accessibility access is
requested only when the user clicks the enable button, never merely by opening the list.
