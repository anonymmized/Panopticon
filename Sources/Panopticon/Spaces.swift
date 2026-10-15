import AppKit

// Space layouts are separate from appearance profiles; switching never changes integrations.
struct BarSpace: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var symbol: String = "house"
    var paths: [String] = []
    var links: [QuickLink] = []
    var collections: [AppCollection] = []
    var desktop: Int?
}

enum DockEdge: String, Codable, CaseIterable {
    case bottom, top, left, right
    var title: String { ["bottom": L("Снизу"), "top": L("Сверху"), "left": L("Слева"), "right": L("Справа")][rawValue]! }
    var isVertical: Bool { self == .left || self == .right }
    var popoverEdge: NSRectEdge {
        switch self { case .bottom: return .maxY; case .top: return .minY; case .left: return .maxX; case .right: return .minX }
    }
}

extension BarModel {
    static let spaceSymbols = ["house", "briefcase", "gamecontroller", "music.note", "paintbrush", "hammer",
                               "book", "globe", "star", "heart", "bolt", "camera", "film", "message",
                               "folder", "terminal", "graduationcap", "leaf"]
    var currentSpace: BarSpace { spaces.first { $0.id == selectedSpaceID } ?? BarSpace(name: L("Главное")) }
    var selectedSpaceIndex: Int { spaces.firstIndex { $0.id == selectedSpaceID } ?? 0 }
    var dockEdge: DockEdge { DockEdge(rawValue: edge) ?? .bottom }
    var dockTheme: DockTheme { DockTheme(rawValue: theme) ?? .dark }

    func selectSpace(_ id: String) {
        guard let space = spaces.first(where: { $0.id == id }), id != selectedSpaceID else { return }
        batch {
            snapshotSpace()
            selectedSpaceID = id
            pinned = space.paths.compactMap { path in
                let url = URL(fileURLWithPath: path)
                return Bundle(url: url)?.bundleIdentifier == nil ? nil : DockItem(url: url)
            }
            quickLinks = space.links; collections = space.collections
        }
    }
    func cycleSpace(_ delta: Int) {
        guard !spaces.isEmpty else { return }
        selectSpace(spaces[((selectedSpaceIndex + delta) % spaces.count + spaces.count) % spaces.count].id)
    }
    @discardableResult func addSpace(name: String, symbol: String = "briefcase") -> String? {
        let name = SettingsRules.label(name)
        guard !name.isEmpty, spaces.count < 30 else { return nil }
        let space = BarSpace(name: name, symbol: symbol)
        spaces.append(space); selectSpace(space.id)
        return space.id
    }
    @discardableResult func renameSpace(_ id: String, name: String) -> Bool {
        let name = SettingsRules.label(name)
        guard !name.isEmpty, let index = spaces.firstIndex(where: { $0.id == id }) else { return false }
        spaces[index].name = name; save(); return true
    }
    func changeSpaceSymbol(_ id: String, symbol: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].symbol = symbol; save()
    }
    func bindSpace(_ id: String, desktop: Int?) {
        guard let index = spaces.firstIndex(where: { $0.id == id }), desktop == nil || (1...30).contains(desktop!) else { return }
        if let desktop { for i in spaces.indices where spaces[i].desktop == desktop { spaces[i].desktop = nil } }
        spaces[index].desktop = desktop; save()
    }
    func removeSpace(_ id: String) {
        guard spaces.count > 1 else { return }
        if id == selectedSpaceID, let replacement = spaces.first(where: { $0.id != id }) { selectSpace(replacement.id) }
        spaces.removeAll { $0.id == id }; save()
    }
    func moveSpace(_ id: String, by offset: Int) {
        guard let i = spaces.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(0, i + offset), spaces.count - 1)
        spaces.swapAt(i, target); save()
    }
    func moveApp(_ item: DockItem, toSpace id: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }), id != selectedSpaceID else { return }
        if !spaces[index].paths.contains(item.id) { spaces[index].paths.append(item.id) }
        remove(item)
    }
    func snapshotSpace() {
        guard let index = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else { return }
        let updated = BarSpace(id: selectedSpaceID, name: spaces[index].name, symbol: spaces[index].symbol,
                               paths: pinned.map(\.id), links: quickLinks, collections: collections,
                               desktop: spaces[index].desktop)
        if spaces[index] != updated { spaces[index] = updated }
    }
    func desktopChanged(_ number: Int?) {
        if currentDesktop != number { currentDesktop = number }
        if autoSwitchDesktops, let number, let space = spaces.first(where: { $0.desktop == number }) { selectSpace(space.id) }
    }
    func badge(for item: DockItem) -> String? {
        badges[item.url.resolvingSymlinksInPath().standardizedFileURL.path]
    }
    func refreshBadges() {
        let next = showBadges ? AX.dockBadges() : [:]
        if badges != next { badges = next; onChange?() }
    }
    static var trashURL: URL { FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory() + "/.Trash") }
    func addFiles(_ urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                if url.pathExtension.lowercased() == "app" { add(url) }
                else {
                    let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    _ = addQuickLink(name: FileManager.default.displayName(atPath: url.path), kind: directory ? "folder" : "file", destination: url.path)
                }
            } else { _ = addQuickLink(name: url.host ?? url.absoluteString, kind: "web", destination: url.absoluteString) }
        }
    }
}
