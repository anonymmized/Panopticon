import AppKit

func runIntegrationTests() throws {
    let suite = "app.newmacbar.integration.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let finder = "/System/Library/CoreServices/Finder.app"
    let calendar = "/System/Applications/Calendar.app"
    defaults.set([finder], forKey: "pinned")
    defaults.set(42.0, forKey: "iconSize")
    defaults.set("https://calendar.google.com", forKey: "calendarWebURL")
    let model = BarModel(defaults: defaults, observe: false)
    let first = model.selectedSpaceID
    precondition(model.spaces.count == 3 && model.pinned.map(\.id) == [finder] && model.iconSize == 42, "Legacy settings migration")
    let work = model.addSpace(name: L("Разработка"))!
    precondition(model.pinned.isEmpty, "New space starts empty")
    model.add(URL(fileURLWithPath: calendar))
    _ = model.addQuickLink(name: L("Файлы"), kind: "folder", destination: "/private/tmp")
    model.updateCollection(AppCollection(name: L("Инструменты"), paths: [finder]))
    var changes = 0; model.onChange = { changes += 1 }
    model.selectSpace(first)
    precondition(changes == 1 && model.pinned.map(\.id) == [finder] && model.quickLinks.isEmpty && model.collections.isEmpty, "Space changes atomically and isolates layouts")
    model.selectSpace(work)
    precondition(model.pinned.map(\.id) == [calendar] && model.quickLinks.count == 1 && model.collections.count == 1, "Space restores complete layout")
    model.moveApp(model.pinned[0], toSpace: first)
    precondition(model.pinned.isEmpty, "Moving app removes its source shortcut")
    model.selectSpace(first)
    precondition(model.pinned.map(\.id) == [finder, calendar], "Moving app preserves destination items")
    model.bindSpace(first, desktop: 1); model.bindSpace(work, desktop: 1)
    precondition(model.spaces.first { $0.id == first }?.desktop == nil, "Desktop binding is unique")
    model.desktopChanged(1)
    precondition(model.selectedSpaceID == work, "Desktop follows bound space")
    model.moveSpace(work, by: -1)
    precondition(model.selectedSpaceID == work, "Reordering preserves selected identity")
    model.edge = "left"; model.theme = "aurora"
    let restored = BarModel(defaults: defaults, observe: false)
    precondition(restored.selectedSpaceID == work && restored.edge == "left" && restored.theme == "aurora" && restored.quickLinks.count == 1, "Spaces and appearance persist")
    model.removeSpace(work)
    precondition(!model.spaces.contains { $0.id == work } && model.spaces.contains { $0.id == model.selectedSpaceID }, "Deleting active space preserves valid selection")

    let fixture: [String: Any] = [
        "spaces": [["name": "FreeDock", "symbol": "star", "items": [
            ["path": finder], ["path": finder], ["path": "/private/tmp"],
            ["path": "https://example.com"], ["path": "javascript:alert(1)"]]]],
        "current": 999, "theme": "sunset", "edge": "right", "iconSize": -100,
        "showMusic": true, "showClock": true, "musicSource": "music"
    ]
    let data = try JSONSerialization.data(withJSONObject: fixture)
    let source = try SettingsArchiveImport.decode(data)
    let converted = source.convertedSpaces()
    precondition(converted[0].paths == [finder] && converted[0].links.count == 2, "FreeDock import deduplication and URL validation")
    let previousCount = model.spaces.count
    let previousTheme = model.theme
    try model.importSettingsArchive(data, appearance: false)
    precondition(model.spaces.count == previousCount + 1 && model.theme == previousTheme && model.calendarWebURL == "https://calendar.google.com", "Import adds spaces and preserves integrations")
    try model.importSettingsArchive(data, appearance: true)
    precondition(model.theme == "sunset" && model.edge == "right" && model.iconSize == 28 && model.widgetKinds == ["clock", "music"], "Import appearance clamps values")
    do { _ = try SettingsArchiveImport.decode(Data(count: 5_000_001)); preconditionFailure("Oversized FreeDock import accepted") } catch SettingsArchiveImport.ImportError.tooLarge { }
    do { _ = try SettingsArchiveImport.decode(Data("{\"spaces\":[]}".utf8)); preconditionFailure("Empty FreeDock import accepted") } catch SettingsArchiveImport.ImportError.invalidSpaces { }
    for id in model.spaces.map(\.id) { model.removeSpace(id) }
    precondition(model.spaces.count == 1, "Final space cannot be removed")
    let appearance = ProfileAppearance(model)
    model.edge = "top"; model.showTrash.toggle(); appearance.apply(to: model)
    precondition(model.edge == appearance.edge && model.showTrash == appearance.showTrash, "Profiles preserve integrated appearance")
    print("PASS: legacy migration, spaces, desktop bindings, cross-space moves, FreeDock import, themes and edges")
}
