import AppKit

func runSelfTests() {
    runPlatformTests()
    runNativeDockModelTests()
    let suite = "app.newmacbar.selftest.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set([String](), forKey: "pinned")
    let model = BarModel(defaults: defaults, observe: false)
    let paths = ["/System/Library/CoreServices/Finder.app", "/System/Applications/Music.app", "/System/Applications/Calendar.app"]
    for path in paths { model.add(URL(fileURLWithPath: path)) }
    precondition(model.pinned.count == 3, "App validation / insertion")
    model.add(URL(fileURLWithPath: paths[0])); precondition(model.pinned.count == 3, "Deduplication")
    model.add(URL(fileURLWithPath: "/private/tmp/not-an-app.txt")); precondition(model.pinned.count == 3, "Reject invalid drop")
    model.move(paths[0], to: 3); precondition(model.pinned.map(\.id) == [paths[1], paths[2], paths[0]], "Move right")
    model.move(paths[0], to: 0); precondition(model.pinned.map(\.id) == paths, "Move left")
    model.move(paths[1], to: 2); precondition(model.pinned.map(\.id) == paths, "Adjacent insertion is no-op")
    model.move(paths[0], to: 999); precondition(model.pinned.last?.id == paths[0], "Clamp boundary")
    model.iconSize = 52; model.widget = "music"
    let restored = BarModel(defaults: defaults, observe: false)
    precondition(restored.pinned == model.pinned && restored.iconSize == 52 && restored.widget == "music", "Persistence")
    model.remove(model.pinned[0]); precondition(model.pinned.count == 2, "Remove")
    model.widgetWidth = 212; model.widgetAccent = "mint"; model.widgetStyle = "compact"
    model.clockSeconds = true; model.replaceDock = false; model.hoverStyle = "scale"
    let group = AppCollection(name: "Работа", paths: paths)
    model.updateCollection(group)
    var updated = group; updated.name = "Фокус"; updated.paths.removeLast()
    model.updateCollection(updated)
    precondition(model.collections.count == 1 && model.collections[0] == updated, "Collection edit")
    let reloaded = BarModel(defaults: defaults, observe: false)
    precondition(reloaded.collections == [updated] && reloaded.widgetWidth == 212 && reloaded.clockSeconds && !reloaded.replaceDock && reloaded.widgetAccent == "mint" && reloaded.widgetStyle == "compact" && reloaded.hoverStyle == "scale", "Detailed settings persistence, collections, widget configuration, focus timer")
    model.removeCollection(group.id); precondition(model.collections.isEmpty, "Collection deletion")
    let focus = FocusTimer(defaults: defaults); focus.reset(minutes: 5); precondition(focus.text == "05:00", "Timer duration")
    focus.toggle(minutes: 5); precondition(focus.isRunning, "Timer start")
    focus.toggle(minutes: 5); precondition(!focus.isRunning && focus.remaining <= 300, "Timer pause")
    focus.reset(minutes: 25); precondition(focus.remaining == 1500 && !focus.isRunning, "Timer reset")
    let appURL = URL(fileURLWithPath: paths[1])
    precondition(ActionRouter.calendarTarget(kind: "app", appPath: paths[1], webURL: "") == .application(appURL), "Custom calendar app")
    precondition(ActionRouter.calendarTarget(kind: "app", appPath: "/private/tmp/missing.app", webURL: "") == nil, "Missing calendar app")
    precondition(ActionRouter.calendarTarget(kind: "web", appPath: "", webURL: "https://calendar.google.com") == .resource(URL(string: "https://calendar.google.com")!), "Web calendar")
    precondition(ActionRouter.calendarTarget(kind: "web", appPath: "", webURL: "javascript:alert(1)") == nil, "Calendar URL validation")
    precondition(!model.addQuickLink(name: "", kind: "web", destination: "https://example.com"), "Empty link label")
    precondition(!model.addQuickLink(name: "Unsafe", kind: "web", destination: "file:///etc/passwd"), "Only web protocols for sites")
    precondition(model.addQuickLink(name: "Example", kind: "web", destination: "https://example.com"), "Add website link")
    precondition(!model.addQuickLink(name: "Duplicate", kind: "web", destination: "https://example.com"), "Website deduplication")
    precondition(model.addQuickLink(name: "Temp", kind: "folder", destination: "/private/tmp"), "Add folder link")
    model.secondaryWidget = "calendar"; precondition(model.widgetKinds == ["music", "calendar"], "Two distinct widgets")
    model.secondaryWidget = "music"; precondition(model.widgetKinds == ["music"], "Duplicate widgets collapse")
    model.secondaryWidget = "calendar"
    model.calendarDestination = "web"; model.calendarWebURL = "https://calendar.google.com"
    model.calendarEventsEnabled = true; model.selectedCalendarIDs = ["test-calendar"]; model.launcherEnabled = false
    model.applyPreset("aurora")
    model.saveProfile(name: "Работа")
    precondition(model.profiles.count == 1, "Create profile")
    let savedProfile = model.profiles[0]
    let before = ProfileAppearance(model)
    var notifications = 0; model.onChange = { notifications += 1 }
    model.applyPreset("electric"); precondition(notifications == 1, "Preset saves atomically")
    model.quickLinks = []; model.pinned = []; model.applyProfile(savedProfile)
    precondition(ProfileAppearance(model) == before && model.quickLinks.count == 2 && !model.pinned.isEmpty, "Profile restores layout and actions")
    precondition(model.calendarWebURL == "https://calendar.google.com" && !model.replaceDock, "Profile preserves external integrations")
    let settings = BarModel(defaults: defaults, observe: false)
    precondition(settings.profiles == model.profiles && settings.quickLinks == model.quickLinks && settings.secondaryWidget == "calendar" && settings.calendarDestination == "web" && settings.selectedCalendarIDs == ["test-calendar"] && settings.calendarEventsEnabled && !settings.launcherEnabled, "New feature persistence")
    model.removeQuickLink(model.quickLinks[0].id); precondition(model.quickLinks.count == 1, "Remove quick link")
    model.deleteProfile(savedProfile.id); precondition(model.profiles.isEmpty, "Delete profile")
    precondition(AppCatalog.searchScore("SAF", in: "Safari") == 0 && AppCatalog.searchScore("vsc", in: "Visual Studio Code") != nil && AppCatalog.searchScore("zzz", in: "Safari") == nil, "Launcher search ranking")
    do { try runRegressionTests(defaults: defaults, model: model) } catch { preconditionFailure("Regression test failed: \(error)") }
    do { try runIntegrationTests() } catch { preconditionFailure("Integration test failed: \(error)") }
    defaults.removePersistentDomain(forName: suite)
    print("PASS: app validation, reorder, persistence, collections, timer, calendar routing, link validation, two widgets, profiles, atomic preset changes, launcher search")
}
