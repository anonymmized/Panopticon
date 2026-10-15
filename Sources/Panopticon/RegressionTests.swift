import AppKit

func runRegressionTests(defaults: UserDefaults, model: BarModel) throws {
    // Adjacent enlarged icons must remain disjoint, including a scaled dock.
    for scale: CGFloat in [1, 0.65] {
        let frames = BarGeometry.frames(sizes: [36, 58, 49, 36], spacing: 8, origin: .zero, scale: scale, base: 36, lift: 7)
        for i in 1..<frames.count { precondition(frames[i - 1].maxX < frames[i].minX, "Magnification overlaps neighboring icons") }
        precondition(BarGeometry.nearest(NSPoint(x: frames[1].midX, y: frames[1].midY), frames: frames) == 1, "Magnified icon hit test")
    }
    model.batch { model.widget = "clock"; model.secondaryWidget = "calendar" }
    model.widget = "calendar"
    precondition(model.secondaryWidget == "none" && model.widgetKinds == ["calendar"], "Duplicate widget selection reconciliation")
    model.batch { model.widget = "music"; model.secondaryWidget = "calendar" }
    var notifications = 0; model.onChange = { notifications += 1 }
    model.batch { model.batch { model.iconSize = 42; model.opacity = 0.2 }; model.cornerRadius = 18 }
    precondition(notifications == 1, "Nested batches must publish once")
    model.saveProfile(name: "Работа"); let first = model.profiles.last!
    model.saveProfile(name: "работа"); precondition(model.profiles.count == 1 && model.profiles[0].id == first.id, "Same named profile must update")
    model.saveProfile(name: "Личное"); precondition(!model.renameProfile(first.id, to: "Личное"), "Duplicate profile rename")
    precondition(model.renameProfile(first.id, to: "Рабочая панель"), "Profile rename")
    model.iconSize = 48; model.updateProfile(first.id); precondition(model.profiles.first!.appearance.iconSize == 48, "Update profile snapshot")
    let data = try ProfileArchive(profile: model.profiles[0]).data()
    let imported = try ProfileArchive.decode(data)
    precondition(imported.id != model.profiles[0].id && imported.appearance == model.profiles[0].appearance, "Portable profile round trip")
    var broken = model.profiles[0]; broken.appearance.iconSize = -500; broken.appearance.magnification = 900; broken.appearance.widget = "unknown"
    let safe = try ProfileArchive.decode(ProfileArchive(profile: broken).data())
    precondition(safe.appearance.iconSize == 28 && safe.appearance.magnification == 1.8 && safe.appearance.widget == "clock", "Imported preferences limits")
    var wrongVersion = try JSONSerialization.jsonObject(with: data) as! [String: Any]; wrongVersion["version"] = 99
    do { _ = try ProfileArchive.decode(JSONSerialization.data(withJSONObject: wrongVersion)); preconditionFailure("Unsupported profile version accepted") } catch ProfileArchive.ArchiveError.version { }
    do { _ = try ProfileArchive.decode(Data(count: 1_000_001)); preconditionFailure("Oversized profile accepted") } catch ProfileArchive.ArchiveError.tooLarge { }
    precondition(SettingsRules.number(.nan, 0...1, fallback: 0.5) == 0.5, "Non-finite preferences")
    defaults.set(-999, forKey: "iconSize"); defaults.set(900, forKey: "magnification"); defaults.set("broken", forKey: "widget")
    let recovered = BarModel(defaults: defaults, observe: false)
    precondition(recovered.iconSize == 28 && recovered.magnification == 1.8 && recovered.widget == "clock", "Corrupted saved preference recovery")

    _ = model.addQuickLink(name: "Search", kind: "web", destination: "https://example.org")
    let link = model.quickLinks.last!; model.moveQuickLink(link.id, by: -1)
    precondition(model.quickLinks.first?.id == link.id, "Reorder quick link")
    var edited = link; edited.name = "New label"; edited.destination = "https://example.org/path"
    precondition(model.updateQuickLink(edited) && model.quickLinks.first?.name == "New label", "Edit quick link")
    edited.destination = "javascript:alert(1)"; precondition(!model.updateQuickLink(edited), "Invalid edited link")
    precondition(AppCatalog.searchScore("ыфафкш", in: "Safari") != nil, "Wrong keyboard layout search")
    precondition(AppCatalog.searchScore("notion cal", in: "Notion Calendar") == 0, "Multiword search")
    precondition(AppCatalog.searchScore("zzz", in: "Safari") == nil, "No match search")

    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))! }
    let leap = MonthGrid.days(for: date(2024, 2, 15), calendar: calendar)
    precondition(leap.compactMap { $0 }.count == 29 && leap.count % 7 == 0, "Leap month grid")
    let overnight = AgendaEvent(id: "event", title: "Overnight", start: date(2026, 10, 13, 23), end: date(2026, 10, 14, 2), allDay: false, calendar: "Test", color: .systemMint)
    precondition(overnight.overlaps(date(2026, 10, 13), in: calendar) && overnight.overlaps(date(2026, 10, 14), in: calendar), "Overnight event day membership")
    let midnight = AgendaEvent(id: "midnight", title: "Ends at midnight", start: date(2026, 10, 13, 20), end: date(2026, 10, 14), allDay: false, calendar: "Test", color: .systemMint)
    precondition(!midnight.overlaps(date(2026, 10, 14), in: calendar), "Exclusive event end date")

    let descriptor = NSAppleEventDescriptor.list()
    for (i, value) in [NSAppleEventDescriptor(string: "Title ||| intact"), NSAppleEventDescriptor(string: "Artist"), NSAppleEventDescriptor(string: "playing"), NSAppleEventDescriptor(double: 10), NSAppleEventDescriptor(double: 120), NSAppleEventDescriptor(string: ""), NSAppleEventDescriptor(double: 150)].enumerated() { descriptor.insert(value, at: i + 1) }
    let track = MusicSnapshot.parse(descriptor)!
    precondition(track.title == "Title ||| intact" && track.volume == 100, "Structured metadata and volume bounds")
    let timestamp = Date(); precondition(track.displayPosition(at: timestamp.addingTimeInterval(5), sampledAt: timestamp) == 15, "Smooth playback timeline")
    precondition(track.displayPosition(at: timestamp.addingTimeInterval(500), sampledAt: timestamp) == 120, "Playback timeline cap")
    precondition(MusicSnapshot.parse(NSAppleEventDescriptor.list()) == nil, "Malformed player reply")

    let focus = FocusTimer(defaults: defaults); focus.reset(minutes: 5); focus.toggle(minutes: 5); focus.toggle(minutes: 5)
    let paused = FocusTimer(defaults: defaults)
    precondition(!paused.isRunning && paused.remaining > 295 && paused.remaining <= 300, "Paused timer restoration")
    focus.toggle(minutes: 5)
    let running = FocusTimer(defaults: defaults)
    precondition(running.isRunning && running.remaining > 295, "Running timer restoration")
    focus.reset(minutes: 25); running.reset(minutes: 25)

    let backup: [String: Any] = ["autohide": false, "autohide-delay": 0.3, "autohide-time-modifier": "__absent__"]
    defaults.set(backup, forKey: "systemDockBackup")
    let failure = DockIntegration(defaults: defaults) { _, args in CommandResult(status: args.contains("autohide-delay") ? 13 : 0, output: "permission denied") }
    failure.restore(); precondition(defaults.dictionary(forKey: "systemDockBackup") != nil, "Failed restore must retain recovery backup")
    let missing = DockIntegration(defaults: defaults) { _, args in
        if args.first == "delete" { return CommandResult(status: 1, output: "missing") }
        if args.first == "read" { return CommandResult(status: 1, output: "does not exist") }
        return CommandResult(status: 0, output: "")
    }
    missing.restore(); precondition(defaults.dictionary(forKey: "systemDockBackup") == nil, "Successful restoration deletes backup")
    print("PASS: geometry, nested updates, profile editing/import, preference recovery, shortcut editing, keyboard layouts, month boundaries, player metadata, persisted timers, Dock recovery")
}


func runPanelSelfTests() {
    _ = NSApplication.shared
    let suite = "app.panopticon.paneltest.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["/System/Library/CoreServices/Finder.app"], forKey: "pinned")
    let model = BarModel(defaults: defaults, observe: false)
    model.showRunning = false; model.showSpaces = false; model.showTrash = false
    let bar = BarView(model: model, music: MusicController(), focus: FocusTimer(defaults: defaults),
                      agenda: CalendarController())
    let panel = BarPanel(contentRect: NSRect(x: 100, y: 100, width: 600, height: 140),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    let root = PassthroughView(frame: NSRect(x: 0, y: 0, width: 600, height: 140))
    panel.contentView = root
    bar.frame = root.bounds
    root.addSubview(bar.glass)
    root.addSubview(bar)
    bar.refresh()
    precondition(bar.acceptsFirstMouse(for: nil), "Inactive-app first click")
    precondition(!panel.canBecomeKey && !panel.canBecomeMain, "Dock must not steal keyboard focus")
    let inside = NSPoint(x: bar.barRect.midX, y: bar.barRect.midY)
    panel.updateMousePassthrough(for: bar, at: panel.convertPoint(toScreen: inside))
    precondition(!panel.ignoresMouseEvents, "Visible bar must receive clicks")
    precondition(root.hitTest(inside) === bar, "Glass must not swallow icon events")
    let outside = NSPoint(x: 300, y: 130)
    panel.updateMousePassthrough(for: bar, at: panel.convertPoint(toScreen: outside))
    precondition(panel.ignoresMouseEvents, "Transparent margin must pass through to other apps")
    precondition(root.hitTest(outside) == nil, "Transparent margin view hit-test")
    panel.updateMousePassthrough(for: bar, at: panel.convertPoint(toScreen: inside))
    precondition(!panel.ignoresMouseEvents, "Pointer re-entry restores interaction")
    let event = NSEvent.mouseEvent(with: .rightMouseDown, location: inside, modifierFlags: [],
                                  timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                  eventNumber: 1, clickCount: 1, pressure: 1)!
    precondition(bar.menu(for: event)?.items.contains { $0.title == L("Настройки Panopticon…") } == true,
                 "Native right-click menu")
    for edge in DockEdge.allCases {
        model.edge = edge.rawValue; model.showSpaces = true; model.showTrash = true
        let size = NSSize(width: bar.preferredWidth, height: bar.preferredHeight)
        panel.setContentSize(size); root.frame = NSRect(origin: .zero, size: size); bar.frame = root.bounds; bar.refresh()
        precondition(bar.bounds.contains(bar.barRect), "Bar surface must fit every screen edge")
        let center = NSPoint(x: bar.barRect.midX, y: bar.barRect.midY)
        panel.updateMousePassthrough(for: bar, at: panel.convertPoint(toScreen: center))
        precondition(!panel.ignoresMouseEvents, "Every edge remains interactive")
        let corner = NSPoint(x: bar.bounds.midX, y: bar.bounds.midY)
        if !bar.containsInteractivePoint(corner) {
            panel.updateMousePassthrough(for: bar, at: panel.convertPoint(toScreen: corner))
            precondition(panel.ignoresMouseEvents, "Every edge passes through transparent margin")
        }
    }
    runDragDropTests(bar: bar, model: model, panel: panel)
    for (language, settingsTitle, trashTitle) in [(AppLanguage.english, "Panopticon settings…", "Trash"), (.russian, "Настройки Panopticon…", "Корзина")] {
        Localization.shared.withTemporaryLanguage(language) {
            bar.refresh()
            precondition(bar.menu(for: event)?.items.contains { $0.title == settingsTitle } == true, "Localized native context menu")
            precondition((bar.accessibilityChildren() as? [BarAccessibilityButton])?.contains { $0.accessibilityLabel() == trashTitle } == true, "Localized accessibility labels")
        }
    }
    print("PASS: panel passthrough, re-entry, first click, glass hit-test, focus and native menu")
}
