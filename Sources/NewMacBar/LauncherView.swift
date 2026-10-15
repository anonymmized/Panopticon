import AppKit
import SwiftUI

final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onClose: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { if let onClose { onClose() } else { orderOut(nil) } }
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
    @State private var selectedID: String?
    @FocusState private var focused: Bool
    private var results: [LauncherResult] {
        var list = catalog.items.map { item in
            LauncherResult(
                id: "app:" + item.id, title: item.name,
                subtitle: model.isRunning(item) ? "Открыто · переключиться" : "Приложение", image: item.icon,
                symbol: "app", action: { model.launch(item) }, pin: { model.add(item.url) })
        }
        list += model.quickLinks.map { link in
            LauncherResult(
                id: link.id, title: link.name,
                subtitle: link.kind == "folder" ? "Папка" : (link.kind == "file" ? "Файл" : "Сайт"),
                image: nil, symbol: link.symbol,
                action: { if let url = link.url { ActionRouter.open(.resource(url)) } })
        }
        list += model.spaces.map { space in
            LauncherResult(
                id: "space:" + space.id, title: space.name,
                subtitle: "Пространство · \(space.paths.count) приложений", image: nil, symbol: space.symbol,
                action: { model.selectSpace(space.id) })
        }
        let catalogPaths = Set(catalog.items.map(\.id))
        var seenLinks = Set<String>()
        for space in model.spaces where space.id != model.selectedSpaceID {
            for path in space.paths where !catalogPaths.contains(path) {
                let item = DockItem(url: URL(fileURLWithPath: path))
                if item.bundleID != nil {
                    list.append(
                        LauncherResult(
                            id: "app:" + path, title: item.name, subtitle: space.name, image: item.icon,
                            symbol: "app", action: { model.launch(item) }, pin: { model.add(item.url) }))
                }
            }
            for link in space.links
            where seenLinks.insert(link.destination).inserted
                && !model.quickLinks.contains(where: { $0.destination == link.destination })
            {
                list.append(
                    LauncherResult(
                        id: "link:" + link.id, title: link.name, subtitle: space.name, image: nil,
                        symbol: link.symbol,
                        action: { if let url = link.url { ActionRouter.open(.resource(url)) } }))
            }
        }
        list.append(
            LauncherResult(
                id: "action:settings", title: "Настройки панели", subtitle: "Действие", image: nil,
                symbol: "slider.horizontal.3",
                action: { NotificationCenter.default.post(name: .openBarSettings, object: nil) }))
        list.append(
            LauncherResult(
                id: "action:toggle", title: model.barVisible ? "Скрыть панель" : "Показать панель",
                subtitle: "Действие", image: nil, symbol: "dock.rectangle",
                action: { model.barVisible.toggle() }))
        var unique = Set<String>()
        list = list.filter { unique.insert($0.id).inserted }
        list += model.profiles.map { profile in
            LauncherResult(
                id: "profile:" + profile.id, title: profile.name, subtitle: "Профиль панели", image: nil,
                symbol: "rectangle.stack.fill", action: { model.applyProfile(profile) })
        }
        list.append(
            LauncherResult(
                id: "calendar", title: "Календарь", subtitle: model.calendarAppName, image: nil,
                symbol: "calendar", action: { model.openCalendar() }))
        return list.compactMap { result -> (LauncherResult, Int)? in
            guard let score = AppCatalog.searchScore(query, in: result.title) else { return nil }
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && result.id.hasPrefix("app:") {
                let path = String(result.id.dropFirst(4))
                let recent = model.recentAppPaths.firstIndex(of: path)
                let pinned = model.pinned.firstIndex(where: { $0.id == path })
                return (result, recent ?? pinned.map { $0 + 20 } ?? 100)
            }
            return (result, query.isEmpty ? 150 : score)
        }.sorted { a, b in
            a.1 == b.1 ? a.0.title.localizedStandardCompare(b.0.title) == .orderedAscending : a.1 < b.1
        }.prefix(30).map(\.0)
    }
    var body: some View {
        let visible = results
        let ids = visible.map(\.id)
        let selection = StableSelection.reconciled(selectedID, in: ids)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(Studio.accent)
                    .accessibilityHidden(true)
                TextField("Приложение, папка, сайт или профиль…", text: $query).font(.system(size: 18))
                    .textFieldStyle(.plain).focused($focused)
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).accessibilityLabel("Закрыть поиск")
            }.padding(22)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(visible) { result in
                            Button {
                                close()
                                result.action()
                            } label: {
                                HStack(spacing: 12) {
                                    if let image = result.image {
                                        Image(nsImage: image).resizable().frame(width: 34, height: 34)
                                            .accessibilityHidden(true)
                                    } else {
                                        Image(systemName: result.symbol).foregroundStyle(Studio.accent).frame(
                                            width: 34, height: 34
                                        ).accessibilityHidden(true)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.title).font(Studio.body.weight(.medium)).lineLimit(1)
                                        Text(result.subtitle).font(Studio.caption).foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if result.id == selection {
                                        Image(systemName: "return").foregroundStyle(.secondary)
                                            .accessibilityHidden(true)
                                    }
                                }.padding(10).background(
                                    result.id == selection ? Studio.accent.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10)
                                ).contentShape(Rectangle())
                            }.buttonStyle(.plain).id(result.id).accessibilityLabel(
                                result.title + ", " + result.subtitle
                            ).accessibilityAddTraits(result.id == selection ? [.isSelected] : [])
                        }
                        if visible.isEmpty {
                            EmptyState(
                                symbol: "magnifyingglass",
                                title: catalog.loading ? "Ищу приложения…" : "Ничего не найдено",
                                detail: "Попробуй другое название или часть слова.")
                        }
                    }.padding(10)
                }.onChange(of: selectedID) { value in if let value { proxy.scrollTo(value, anchor: .center) }
                }
            }
            Divider()
            HStack {
                Text("↑ ↓ выбрать   ↵ открыть   ⌘↵ закрепить")
                Spacer()
                Text(model.launcherShortcutLabel)
            }.font(Studio.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Studio.canvas).clipShape(
            RoundedRectangle(cornerRadius: Studio.radius)
        )
        .background(
            KeyboardCommands { event in
                switch event.keyCode {
                case 53:
                    close()
                    return true
                case 125:
                    selectedID = StableSelection.moved(selection, in: ids, by: 1)
                    return true
                case 126:
                    selectedID = StableSelection.moved(selection, in: ids, by: -1)
                    return true
                case 36, 76:
                    guard let selection, let item = visible.first(where: { $0.id == selection }) else {
                        return true
                    }
                    if event.modifierFlags.contains(.command) {
                        // An unsupported pin action must never turn into an accidental launch.
                        guard let pin = item.pin else { return true }
                        pin()
                        close()
                    } else {
                        close()
                        item.action()
                    }
                    return true
                default: return false
                }
            }
        )
        .onAppear {
            focused = true
            selectedID = ids.first
        }
        .onChange(of: query) { _ in selectedID = nil }
        .onChange(of: ids) { value in selectedID = StableSelection.reconciled(selectedID, in: value) }
        .onExitCommand(perform: close)
    }
}

extension Notification.Name { static let openBarSettings = Notification.Name("NewMacBar.openSettings") }
