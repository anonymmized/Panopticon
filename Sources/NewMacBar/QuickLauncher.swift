import SwiftUI
import AppKit
import Carbon

final class GlobalShortcut {
    var action: (() -> Void)?
    private var localMonitor: Any?
    private var lastTrigger = Date.distantPast
    private var keyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var registered = false
    init(choice: String, action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            var hotKey = EventHotKeyID()
            guard let event,
                  GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey) == noErr,
                  hotKey.signature == 0x4E4D4252, hotKey.id == 1 else { return OSStatus(eventNotHandledErr) }
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().trigger()
            return noErr
        }, 1, &event, context, &handlerRef)
        let modifiers = choice == "commandShiftSpace" ? UInt32(cmdKey | shiftKey) : (choice == "optionShiftSpace" ? UInt32(optionKey | shiftKey) : UInt32(controlKey | optionKey))
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let desired: NSEvent.ModifierFlags = choice == "commandShiftSpace" ? [.command, .shift] : (choice == "optionShiftSpace" ? [.option, .shift] : [.control, .option])
            let actual = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == UInt16(kVK_Space), actual == desired { self?.trigger(); return nil }
            return event
        }
        if status == noErr { registered = RegisterEventHotKey(UInt32(kVK_Space), modifiers, EventHotKeyID(signature: 0x4E4D4252, id: 1), GetEventDispatcherTarget(), 0, &keyRef) == noErr }
    }
    private func trigger() { guard Date().timeIntervalSince(lastTrigger) > 0.2 else { return }; lastTrigger = Date(); action?() }
    deinit { if let localMonitor { NSEvent.removeMonitor(localMonitor) }; if let keyRef { UnregisterEventHotKey(keyRef) }; if let handlerRef { RemoveEventHandler(handlerRef) } }
}

final class AppCatalog: ObservableObject {
    @Published private(set) var items: [DockItem] = []
    @Published private(set) var loading = false
    private var refreshed = Date.distantPast
    private let queue = DispatchQueue(label: "NewMacBar.app-catalog", qos: .userInitiated)
    func refresh(force: Bool = false) {
        guard !loading, force || Date().timeIntervalSince(refreshed) > 120 else { return }
        loading = true; refreshed = Date()
        queue.async { [weak self] in
            let manager = FileManager.default
            var urls = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
            for path in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"] {
                guard let enumerator = manager.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let url as URL in enumerator {
                    if url.pathExtension.lowercased() == "app" { urls.append(url); enumerator.skipDescendants() }
                    else if enumerator.level >= 2 { enumerator.skipDescendants() }
                }
            }
            var seen = Set<String>(); let discovered = urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
            DispatchQueue.main.async { guard let self else { return }; self.items = discovered.map { DockItem(url: $0) }.filter { $0.bundleID != nil }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }; self.loading = false }
        }
    }
    static func searchScore(_ query: String, in name: String) -> Int? {
        let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).filter { !$0.isWhitespace }
        let n = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).filter { !$0.isWhitespace }
        func score(_ q: String) -> Int? {
            if q.isEmpty || n.hasPrefix(q) { return 0 }
            if n.contains(q) { return 20 }
            var cursor = n.startIndex; var gaps = 0
            for char in q { guard let index = n[cursor...].firstIndex(of: char) else { return nil }; gaps += n.distance(from: cursor, to: index); cursor = n.index(after: index) }
            return 40 + gaps
        }
        let russian = Array("йцукенгшщзхъфывапролджэячсмитьбю")
        let latin = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.")
        let toLatin = Dictionary(uniqueKeysWithValues: zip(russian, latin)); let toRussian = Dictionary(uniqueKeysWithValues: zip(latin, russian))
        let variants = [q, String(q.map { toLatin[$0] ?? $0 }), String(q.map { toRussian[$0] ?? $0 })]
        return variants.enumerated().compactMap { index, value in score(value).map { $0 + (index == 0 ? 0 : 8) } }.min()
    }

}

final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

struct LauncherResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let image: NSImage?
    let symbol: String
    let action: () -> Void
    var pin: (() -> Void)? = nil
}

struct QuickLauncherView: View {
    @ObservedObject var model: BarModel
    @ObservedObject var catalog: AppCatalog
    let close: () -> Void
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool
    private var results: [LauncherResult] {
        var list = catalog.items.map { item in LauncherResult(id: "app:" + item.id, title: item.name, subtitle: model.isRunning(item) ? "Открыто · переключиться" : "Приложение", image: item.icon, symbol: "app", action: { model.launch(item) }, pin: { model.add(item.url) }) }
        list += model.quickLinks.map { link in LauncherResult(id: link.id, title: link.name, subtitle: link.kind == "folder" ? "Папка" : (link.kind == "file" ? "Файл" : "Сайт"), image: nil, symbol: link.symbol, action: { if let url = link.url { ActionRouter.open(.resource(url)) } }) }
        list += model.spaces.map { space in LauncherResult(id: "space:" + space.id, title: space.name, subtitle: "Пространство · \(space.paths.count) приложений", image: nil, symbol: space.symbol, action: { model.selectSpace(space.id) }) }
        let catalogPaths = Set(catalog.items.map(\.id))
        var seenLinks = Set<String>()
        for space in model.spaces where space.id != model.selectedSpaceID {
            for path in space.paths where !catalogPaths.contains(path) {
                let item = DockItem(url: URL(fileURLWithPath: path))
                if item.bundleID != nil { list.append(LauncherResult(id: "app:" + path, title: item.name, subtitle: space.name, image: item.icon, symbol: "app", action: { model.launch(item) }, pin: { model.add(item.url) })) }
            }
            for link in space.links where seenLinks.insert(link.destination).inserted && !model.quickLinks.contains(where: { $0.destination == link.destination }) {
                list.append(LauncherResult(id: "link:" + link.id, title: link.name, subtitle: space.name, image: nil, symbol: link.symbol, action: { if let url = link.url { ActionRouter.open(.resource(url)) } }))
            }
        }
        list.append(LauncherResult(id: "action:settings", title: "Настройки панели", subtitle: "Действие", image: nil, symbol: "slider.horizontal.3", action: { NotificationCenter.default.post(name: .openBarSettings, object: nil) }))
        list.append(LauncherResult(id: "action:toggle", title: model.barVisible ? "Скрыть панель" : "Показать панель", subtitle: "Действие", image: nil, symbol: "dock.rectangle", action: { model.barVisible.toggle() }))
        var unique = Set<String>(); list = list.filter { unique.insert($0.id).inserted }
        list += model.profiles.map { profile in LauncherResult(id: profile.id, title: profile.name, subtitle: "Профиль панели", image: nil, symbol: "rectangle.stack.fill", action: { model.applyProfile(profile) }) }
        list.append(LauncherResult(id: "calendar", title: "Календарь", subtitle: model.calendarAppName, image: nil, symbol: "calendar", action: { model.openCalendar() }))
        return list.compactMap { result -> (LauncherResult, Int)? in guard let score = AppCatalog.searchScore(query, in: result.title) else { return nil }
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && result.id.hasPrefix("app:") {
                let path = String(result.id.dropFirst(4))
                let recent = model.recentAppPaths.firstIndex(of: path)
                let pinned = model.pinned.firstIndex(where: { $0.id == path })
                return (result, recent ?? pinned.map { $0 + 20 } ?? 100)
            }
            return (result, query.isEmpty ? 150 : score) }.sorted { a, b in a.1 == b.1 ? a.0.title.localizedStandardCompare(b.0.title) == .orderedAscending : a.1 < b.1 }.prefix(30).map(\.0)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) { Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(.mint); TextField("Приложение, папка, сайт или профиль…", text: $query).font(.system(size: 17)).textFieldStyle(.plain).focused($focused).onSubmit { runSelected(pin: NSApp.currentEvent?.modifierFlags.contains(.command) == true) }; Text("ESC").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary).padding(5).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5)) }.padding(22)
            Divider().opacity(0.3)
            ScrollViewReader { proxy in ScrollView { VStack(spacing: 3) { ForEach(Array(results.enumerated()), id: \.element.id) { index, result in Button { close(); result.action() } label: { HStack(spacing: 12) { if let image = result.image { Image(nsImage: image).resizable().frame(width: 31, height: 31) } else { Image(systemName: result.symbol).foregroundStyle(.mint).frame(width: 31, height: 31) }; VStack(alignment: .leading, spacing: 3) { Text(result.title).font(.system(size: 12, weight: .medium)); Text(result.subtitle).font(.system(size: 9)).foregroundStyle(.secondary) }; Spacer(); if index == selected { Image(systemName: "return").font(.system(size: 12)).foregroundStyle(.secondary) } }.padding(10).background(index == selected ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).id(index) } }.padding(10) }.onChange(of: selected) { value in proxy.scrollTo(value, anchor: .center) } }
            if results.isEmpty { Text(catalog.loading ? "Загружаю приложения…" : "Ничего не найдено").font(.system(size: 12)).foregroundStyle(.secondary).padding(30) }
            Divider().opacity(0.3)
            HStack { Text("↑ ↓ выбрать    ↵ открыть    ⌘↵ закрепить"); Spacer(); Text(model.launcherShortcutLabel).foregroundStyle(.mint) }.font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
        }.frame(width: 590, height: 420).background(Color(red: 0.07, green: 0.075, blue: 0.10)).clipShape(RoundedRectangle(cornerRadius: 17)).preferredColorScheme(.dark).onAppear { focused = true }.onChange(of: query) { _ in selected = 0 }.onMoveCommand { direction in if direction == .down { selected = results.isEmpty ? 0 : min(selected + 1, results.count - 1) }; if direction == .up { selected = max(0, selected - 1) } }.onExitCommand(perform: close)
    }
    private func runSelected(pin: Bool = false) { guard !results.isEmpty else { return }; let item = results[min(max(selected, 0), results.count - 1)]; close(); if pin, let pin = item.pin { pin() } else { item.action() } }
}

extension Notification.Name { static let openBarSettings = Notification.Name("NewMacBar.openSettings") }
