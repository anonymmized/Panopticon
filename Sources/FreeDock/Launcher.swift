import AppKit
import SwiftUI

// MARK: - Installed apps

final class AppCatalog {
    static let shared = AppCatalog()
    private(set) var apps: [URL] = []
    private var loading = false

    private static let roots = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    func refresh(completion: @escaping () -> Void) {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [String: URL] = [:]
            let fm = FileManager.default
            func scan(_ dir: URL, depth: Int) {
                let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles])) ?? []
                for entry in entries {
                    if entry.pathExtension == "app" {
                        found[entry.lastPathComponent] = found[entry.lastPathComponent] ?? entry
                    } else if depth > 0 {
                        var isDirectory: ObjCBool = false
                        if fm.fileExists(atPath: entry.path, isDirectory: &isDirectory), isDirectory.boolValue {
                            scan(entry, depth: depth - 1)
                        }
                    }
                }
            }
            for root in Self.roots { scan(URL(fileURLWithPath: root), depth: 1) }
            found["Finder.app"] = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
            let sorted = found.values.sorted { $0.lastPathComponent < $1.lastPathComponent }
            DispatchQueue.main.async {
                self.apps = sorted
                self.loading = false
                completion()
            }
        }
    }
}

// MARK: - Matching

enum FuzzyMatch {
    private static let ru = Array("йцукенгшщзхъфывапролджэячсмитьбю")
    private static let en = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.")

    /// Text typed with the wrong keyboard layout: "ыфаф" ↔ "safa".
    static func swapLayout(_ text: String) -> String {
        String(text.map { char -> Character in
            if let i = ru.firstIndex(of: char) { return en[i] }
            if let i = en.firstIndex(of: char) { return ru[i] }
            return char
        })
    }

    /// Higher is better; nil means no match. Understands prefixes, word starts, initials
    /// ("vsc" → Visual Studio Code) and letters in order.
    static func score(_ query: String, _ text: String) -> Int? {
        let q = query.lowercased()
        let t = text.lowercased()
        guard !q.isEmpty else { return 1 }
        if t == q { return 1000 }
        if t.hasPrefix(q) { return 900 - min(100, t.count - q.count) }
        let words = t.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: { $0.hasPrefix(q) }) { return 750 }
        let initials = String(words.compactMap(\.first))
        if initials.hasPrefix(q) { return 650 }
        if t.contains(q) { return 500 }
        var index = t.startIndex
        var gaps = 0
        for char in q {
            guard let found = t[index...].firstIndex(of: char) else { return nil }
            gaps += t.distance(from: index, to: found)
            index = t.index(after: found)
        }
        return max(100, 400 - gaps * 10)
    }

    static func best(_ query: String, _ text: String) -> Int? {
        let direct = score(query, text)
        let swapped = score(swapLayout(query.lowercased()), text).map { $0 - 50 }
        switch (direct, swapped) {
        case let (a?, b?): return max(a, b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }
}

// MARK: - Model

struct LaunchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: NSImage
    let score: Int
    /// Something that can be pinned to the bar with ⌘↩.
    let pinURL: URL?
    let run: () -> Void
}

final class LauncherModel: ObservableObject {
    @Published var query = "" { didSet { update() } }
    @Published private(set) var results: [LaunchResult] = []
    @Published var selection = 0
    @Published private(set) var shownAt = Date()

    private let store: DockStore
    var close: () -> Void = {}
    var openSettings: () -> Void = {}

    init(store: DockStore) {
        self.store = store
    }

    func prepare() {
        query = ""
        shownAt = Date()
        update()
        AppCatalog.shared.refresh { [weak self] in self?.update() }
    }

    private func symbolImage(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }

    func update() {
        let q = query.trimmingCharacters(in: .whitespaces)
        var list: [LaunchResult] = []
        var seen = Set<String>()

        func consider(_ id: String, _ title: String, _ subtitle: String, icon: @autoclosure () -> NSImage,
                      pin: URL? = nil, bonus: Int = 0, run: @escaping () -> Void) {
            guard !seen.contains(id), let score = FuzzyMatch.best(q, title) else { return }
            seen.insert(id)
            list.append(LaunchResult(id: id, title: title, subtitle: subtitle, icon: icon(),
                                     score: score + bonus, pinURL: pin, run: run))
        }

        let store = self.store
        for (index, space) in store.config.spaces.enumerated() {
            for item in space.items {
                let key = item.isWeb ? item.path : DockStore.key(item.url)
                consider(key, item.name, item.isWeb ? item.path : "В баре · \(space.name)",
                         icon: IconCache.shared.icon(for: item), bonus: index == store.config.current ? 40 : 20) {
                    store.open(item)
                }
            }
        }
        for url in AppCatalog.shared.apps {
            let name = url.deletingPathExtension().lastPathComponent
            consider(DockStore.key(url), name, "Приложение", icon: IconCache.shared.icon(for: url.path), pin: url) {
                NSWorkspace.shared.open(url)
            }
        }
        if !q.isEmpty {
            for (index, space) in store.config.spaces.enumerated() {
                consider("space-\(space.id)", space.name, "Пространство", icon: symbolImage(space.symbol)) {
                    store.select(index)
                }
            }
            let actions: [(String, String, () -> Void)] = [
                ("Настройки FreeDock", "gearshape", { [weak self] in self?.openSettings() }),
                (store.config.visible ? "Скрыть бар" : "Показать бар", "dock.rectangle", { store.config.visible.toggle() }),
                ("Новое пространство", "plus.square.on.square", { DispatchQueue.main.async { store.addSpace() } }),
                ("Таймер фокуса: старт / пауза", "timer", { store.focus.toggle() }),
                ("Открыть Корзину", "trash", { NSWorkspace.shared.open(DockStore.trashURL) }),
            ]
            for (title, symbol, run) in actions {
                consider("action-\(title)", title, "Действие", icon: symbolImage(symbol), run: run)
            }
        }

        if q.isEmpty {
            // Without a query: what's in the current space first, then everything else alphabetically.
            list.sort { $0.score != $1.score ? $0.score > $1.score : $0.title < $1.title }
        } else {
            list.sort { $0.score != $1.score ? $0.score > $1.score : $0.title.count < $1.title.count }
        }
        results = Array(list.prefix(40))
        selection = min(selection, max(0, results.count - 1))
        if q.isEmpty || selection >= results.count { selection = 0 }
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func runSelected() {
        guard results.indices.contains(selection) else { return }
        let result = results[selection]
        close()
        result.run()
    }

    func pinSelected() {
        guard results.indices.contains(selection), let url = results[selection].pinURL else {
            NSSound.beep()
            return
        }
        store.add(urls: [url])
        store.flash("Добавлено в «\(store.current.name)»")
        close()
    }
}

// MARK: - Window

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class LauncherController: NSObject, NSWindowDelegate {
    private let model: LauncherModel
    private let panel: LauncherPanel
    private var keyMonitor: Any?

    init(store: DockStore, openSettings: @escaping () -> Void) {
        model = LauncherModel(store: store)
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
                              styleMask: [.borderless, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LauncherView(model: model))
        model.close = { [weak self] in self?.hide() }
        model.openSettings = openSettings
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        model.prepare()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2,
                                         y: area.minY + area.height * 0.62 - panel.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
    }

    func hide() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// Returns nil when the key was handled.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel else { return event }
        switch Int(event.keyCode) {
        case 125: model.move(1); return nil                 // ↓
        case 126: model.move(-1); return nil                // ↑
        case 53: hide(); return nil                         // esc
        case 36, 76:                                        // ↩
            if event.modifierFlags.contains(.command) {
                model.pinSelected()
            } else {
                model.runSelected()
            }
            return nil
        default:
            return event
        }
    }
}

private struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Приложения, файлы, сайты, пространства…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($focused)
            }
            .padding(.horizontal, 18)
            .frame(height: 60)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                            ResultRow(result: result, selected: index == model.selection)
                                .id(index)
                                .onTapGesture {
                                    model.selection = index
                                    model.runSelected()
                                }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.selection) { proxy.scrollTo($0) }
            }

            if model.results.isEmpty {
                Text("Ничего не найдено")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack(spacing: 16) {
                Label("открыть", systemImage: "return")
                Label("закрепить в баре", systemImage: "command")
                Label("выбрать", systemImage: "arrow.up.arrow.down")
                Spacer()
                Text("esc — закрыть")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 34)
        }
        .frame(width: 640, height: 460)
        .background(BlurBackground().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
        .onAppear { focused = true }
        .onChange(of: model.shownAt) { _ in focused = true }
    }
}

private struct ResultRow: View {
    let result: LaunchResult
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: result.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title).font(.system(size: 14, weight: .medium))
                Text(result.subtitle).font(.system(size: 11)).foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
            .lineLimit(1)
            Spacer()
            if selected && result.pinURL != nil {
                Text("⌘↩ в бар").font(.caption).foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
    }
}
