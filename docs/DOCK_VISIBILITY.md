# Dock visibility corrections — 0.6.2

## Trigger rules

For an autohidden Dock, a background update never reveals the panel. Startup,
activation of another app, app launch/termination, screen wake, reopened settings
and settings on another desktop keep it hidden. A window-ordering gate also
rejects incidental system requests to order a hidden panel to the front.

An edge hover reveals after 80 ms. Pressing a mouse button by itself is not a
hover; an intentional drag can reveal after 250 ms so files can still be dropped.
Leaving the bar hides it after 280 ms. An anchored popover or a drag can retain
an already open bar, but cannot summon a hidden one. The existing explicit
**Показать панель** command is still available and holds the bar for one second.

In Mission Control/App Exposé, NewMacBar yields to the native Dock. After an
observed overview closes, the pointer must leave the edge and enter it again;
the old hover cannot be replayed. Sleep/resume similarly does not force a reveal.
Always-visible mode still works outside Mission Control.

## Implementation and compatibility

`DockVisibilityPolicy` is a pure state machine, independent of model updates and
window rendering. It does not add model preferences or change stored spaces,
profiles, native launchers or the Dock recovery backup.

The panel retains AppKit's documented `.transient` behavior, which hides it in
Mission Control ([Apple documentation](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/transient)).
An extra detector reads only owner PID, layer, sharing state and bounds from
CoreGraphics window metadata to avoid explicit re-ordering during the overview.
It never reads window titles or captures images and asks for no permissions.
The observed Dock layer-18 overlay is an undocumented heuristic, informed by
[the primary Tahoe detector example](https://gist.github.com/usagimaru/812b493ca27cac707e76917f7a9bf6a9);
AppKit's `.transient` behavior remains the fallback. Bounds are checked against
actual displays, including negative display origins. Metadata is sampled at most
every 150 ms and only while a panel is visible or a pointer is at its reveal edge.

## Reproduction and validation

`--self-test` includes click/activation/settings replay, startup, hover/drag dwell,
popover retention, explicit commands, wake, overview handoff, re-arming and
metadata false-positive regressions. `--panel-self-test` exercises the real
nonactivating panel, window-ordering gate and injected overview transitions.
All automated tests use isolated preferences.

For live diagnosis without UI activation or file contents:

```sh
/Applications/NewMacBar.app/Contents/MacOS/NewMacBar --visibility-state
```

The command queries only the running process and returns visibility booleans,
the PID and the pin count. It never opens or changes the panel. It uses a
nonce-matched local notification response with a two-second timeout.

## Live verification on macOS 26.6.2 / Apple Silicon

The universal 0.6.2 app was installed locally with an app ZIP backup and a
mode-0600 preferences backup. The actual running process was queried before and
after actions in its permitted CUA surface:

| Scenario | Hidden | Panel visible | Overview detected | Overview suppression |
| --- | --- | --- | --- | --- |
| Startup with settings open | true | false | false | false |
| Settings clicks and applying the native preset | true | false | false | false |
| Actual Mission Control, including an explicit reveal hotkey | true | false | true | true |
| Return from Mission Control while the pointer is elsewhere | true | false | false | false |
| Settings closed, ordinary idle desktop | true | false | false | false |

Presentation permission remained false in all these states. The final running
instance retains 11 launchers, auto-hide enabled and full icon animations.
Exiting an overview away from the edge clears suppression; an AppKit regression
also verifies that the first new edge hover reveals the panel.

Mission Control was entered/exited using the system Mission Control application
through CUA; the system's metadata and the app's actual window state confirmed
the transitions. A physical trackpad swipe has not been exercised by automation.
Live Finder activation was not exercised: automatic approval review rejected
the action with **“Computer Use was not approved to use Finder”**. No Finder
actions followed. App activation/running-list updates are covered by the isolated
real-window regression. Physical pointer hover remains covered by the AppKit
tracking/edge tests rather than a visual CUA claim.

Both self-test modes, native release compilation, universal arm64/x86_64
compilation and signature validation passed. Intel execution and older macOS
versions remain outside this live verification.
