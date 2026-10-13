import SwiftUI
import UniformTypeIdentifiers

private struct SizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Item ids travel as plain text while dragging inside the bar; anything carrying a URL
/// (files from Finder, links from a browser) comes from outside.
private func isInternalDrag(_ info: DropInfo, _ store: DockStore) -> Bool {
    store.dragging != nil && !info.hasItemsConforming(to: [.url])
}

struct DockView: View {
    @ObservedObject var store: DockStore
    var onSize: (CGSize) -> Void

    @State private var dropTargeted = false

    var body: some View {
        let config = store.config
        let edge = config.edge
        let size = CGFloat(config.iconSize)
        let shape = RoundedRectangle(cornerRadius: min(CGFloat(config.cornerRadius), size * 0.6), style: .continuous)
        let running = store.unpinnedRunning
        // Transparent room for magnified icons, labels and the space name.
        let room = (config.magnify ? size * CGFloat(config.magnification - 1) : 0) + (edge.isVertical ? 220 : 44)

        stack(edge.isVertical, spacing: CGFloat(config.iconSpacing)) {
            SpaceSwitcher(store: store)

            Separator(edge: edge, length: size * 0.8)

            ForEach(store.current.items) { item in
                DockItemView(store: store, item: item, pinned: true)
            }

            if store.current.items.isEmpty {
                Group {
                    if edge.isVertical {
                        Image(systemName: "tray.and.arrow.down")
                    } else {
                        Text("Перетащи сюда приложения, папки, файлы или ссылки")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(minWidth: size, minHeight: size)
            }

            AddButton(store: store, size: size)

            if !running.isEmpty {
                Separator(edge: edge, length: size * 0.8)
                ForEach(running) { item in
                    DockItemView(store: store, item: item, pinned: false)
                }
            }

            if config.showTrash {
                Separator(edge: edge, length: size * 0.8)
                TrashView(store: store)
            }

            if WidgetsView.anyEnabled(config) {
                Separator(edge: edge, length: size * 0.8)
                WidgetsView(store: store)
            }
        }
        .padding(10)
        .background(ThemedBackground(theme: config.theme, strength: config.tint).clipShape(shape))
        .overlay(shape.strokeBorder(dropTargeted ? config.theme.accent : Color.white.opacity(0.18),
                                    lineWidth: dropTargeted ? 2 : 1))
        .shadow(color: .black.opacity(0.28), radius: 9, y: 2)
        .overlay(alignment: edge.inwardAlignment) {
            if let toast = store.toast, store.dragging == nil {
                Bubble(text: toast, large: true)
                    .outside(edge, distance: 10)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.url], isTargeted: $dropTargeted) { providers in
            loadURLs(providers) { store.add(urls: $0) }
            return true
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .animation(.easeInOut(duration: 0.18), value: store.current.items)
        .padding(10)
        .padding(edge.inward, room)
        .fixedSize()
        .background(GeometryReader { Color.clear.preference(key: SizeKey.self, value: $0.size) })
        .onPreferenceChange(SizeKey.self, perform: onSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.outerAlignment)
    }
}

private struct Separator: View {
    let edge: DockEdge
    let length: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.2))
            .frame(width: edge.isVertical ? length : 1, height: edge.isVertical ? 1 : length)
    }
}

struct Bubble: View {
    let text: String
    var large = false

    var body: some View {
        Text(text)
            .font(.system(size: large ? 14 : 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, large ? 12 : 8)
            .padding(.vertical, large ? 6 : 3)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .foregroundColor(.white)
            .fixedSize()
    }
}

private struct AddButton: View {
    @ObservedObject var store: DockStore
    let size: CGFloat

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: size * 0.3, weight: .semibold))
            .frame(width: size * 0.66, height: size * 0.66)
            .background(Circle().fill(Color.primary.opacity(0.08)))
            .foregroundStyle(.secondary)
            .contentShape(Circle())
            .onTapGesture { showMenu() }
            .help("Добавить в «\(store.current.name)»")
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem("Приложения, файлы, папки…") { [store] in
            DispatchQueue.main.async { store.chooseFiles() }
        })
        menu.addItem(ActionMenuItem("Ссылка на сайт…") { [store] in
            DispatchQueue.main.async { store.addLink() }
        })
        menu.addItem(ActionMenuItem("Найти приложение…  ⌃⌥Пробел") {
            NotificationCenter.default.post(name: .showLauncher, object: nil)
        })
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

extension Notification.Name {
    static let showLauncher = Notification.Name("FreeDock.showLauncher")
}

// MARK: - Spaces

struct SpaceSwitcher: View {
    @ObservedObject var store: DockStore

    var body: some View {
        stack(store.config.edge.isVertical, spacing: 4) {
            ForEach(Array(store.config.spaces.enumerated()), id: \.element.id) { index, space in
                SpacePill(store: store, index: index, space: space)
            }

            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 20)
                .foregroundStyle(.secondary)
                .contentShape(Circle())
                .onTapGesture { DispatchQueue.main.async { store.addSpace() } }
                .help("Новое пространство")
        }
    }
}

private struct SpacePill: View {
    @ObservedObject var store: DockStore
    let index: Int
    let space: DockSpace

    @State private var targeted = false

    var body: some View {
        let selected = index == store.config.current
        let expanded = selected && !store.config.edge.isVertical

        HStack(spacing: 5) {
            Image(systemName: space.symbol)
            if expanded {
                Text(space.name).lineLimit(1)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, expanded ? 10 : 0)
        .frame(minWidth: 26, minHeight: 26)
        .background(Capsule().fill(selected ? store.config.theme.accent
                                   : Color.primary.opacity(targeted ? 0.3 : 0.08)))
        .foregroundStyle(selected ? Color.white : Color.secondary)
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.18), value: expanded)
        .onTapGesture { store.select(index) }
        .help(index < 9 ? "\(space.name)  ⌃⌥\(index + 1)" : space.name)
        .onDrop(of: [.url, .text], delegate: SpaceDropDelegate(store: store, index: index, targeted: $targeted))
        .overlay(RightClickMenu { store.spaceMenu(for: index) })
    }
}

private struct SpaceDropDelegate: DropDelegate {
    let store: DockStore
    let index: Int
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.url]) || store.dragging != nil
    }

    func dropEntered(info: DropInfo) { targeted = true }

    func dropExited(info: DropInfo) { targeted = false }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        if isInternalDrag(info, store), let id = store.dragging {
            store.dragging = nil
            store.move(id, toSpace: index)
            return true
        }
        loadURLs(info.itemProviders(for: [.url])) { store.add(urls: $0, to: index) }
        return true
    }
}

// MARK: - Items

struct DockItemView: View {
    @ObservedObject var store: DockStore
    let item: DockItem
    /// false for running apps that are only shown, not pinned.
    let pinned: Bool

    @State private var hover = false
    @State private var bouncing = false
    @State private var showStack = false
    @State private var dropTarget = false

    var body: some View {
        let config = store.config
        let edge = config.edge
        let size = CGFloat(config.iconSize)
        let dragged = store.dragging == item.id
        let grow = (config.magnify && hover && store.dragging == nil) || dropTarget
        let scale: CGFloat = grow ? CGFloat(config.magnification) : 1
        let launching = store.isLaunching(item)

        icon(size: size, scale: scale, edge: edge, dragged: dragged)
            .overlay(alignment: edge.outerAlignment) {
                Indicator(style: config.indicator, running: store.isRunning(item),
                          active: config.highlightActive && store.isActive(item),
                          accent: config.theme.accent, edge: edge)
            }
            .overlay(alignment: edge.inwardAlignment) {
                if hover && config.showLabels && store.dragging == nil && !showStack {
                    Bubble(text: item.name)
                        .outside(edge, distance: size * (scale - 1) + 8)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { tap() }
            .onDrag {
                guard pinned else { return NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                store.dragging = item.id
                return NSItemProvider(object: item.id.uuidString as NSString)
            }
            .onDrop(of: [.url, .text],
                    delegate: ItemDropDelegate(store: store, target: item, pinned: pinned, highlighted: $dropTarget))
            .overlay(RightClickMenu { store.itemMenu(for: item, pinned: pinned) })
            .popover(isPresented: $showStack, arrowEdge: edge.arrowEdge) {
                StackView(folder: item.url) { showStack = false }
            }
            .help(config.showLabels ? "" : item.name)
            .onChange(of: launching) { setBounce($0) }
            .onAppear { if launching { setBounce(true) } }
    }

    private func icon(size: CGFloat, scale: CGFloat, edge: DockEdge, dragged: Bool) -> some View {
        Image(nsImage: IconCache.shared.icon(for: item))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: item.isWeb ? size * 0.22 : 0, style: .continuous))
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) { badge(size: size) }
            .opacity(item.exists ? 1 : 0.35)
            .opacity(dragged ? 0.35 : 1)
            .scaleEffect(scale, anchor: edge.anchor)
            .offset(bouncing ? edge.inwardOffset(size * 0.3) : CGSize.zero)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: scale)
    }

    @ViewBuilder
    private func badge(size: CGFloat) -> some View {
        if let text = store.badge(for: item) {
            Text(text)
                .font(.system(size: max(10, size * 0.22), weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .frame(minWidth: size * 0.38, minHeight: size * 0.38)
                .background(Capsule().fill(Color.red))
                .offset(x: size * 0.1, y: -size * 0.1)
        }
    }

    private func tap() {
        if item.isFolder {
            NSApp.activate(ignoringOtherApps: true)
            showStack.toggle()
        } else {
            store.open(item)
        }
    }

    private func setBounce(_ on: Bool) {
        if on {
            withAnimation(.easeInOut(duration: 0.32).repeatForever(autoreverses: true)) { bouncing = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { bouncing = false }
        }
    }
}

private struct Indicator: View {
    let style: IndicatorStyle
    let running: Bool
    let active: Bool
    let accent: Color
    let edge: DockEdge

    var body: some View {
        if running && style != .hidden {
            let color = active ? accent : Color.primary.opacity(0.75)
            Group {
                if style == .dot {
                    Circle().fill(color).frame(width: active ? 5 : 4, height: active ? 5 : 4)
                } else {
                    Capsule().fill(color)
                        .frame(width: edge.isVertical ? 3 : (active ? 18 : 10),
                               height: edge.isVertical ? (active ? 18 : 10) : 3)
                }
            }
            .offset(edge.inwardOffset(-7))
            .animation(.easeInOut(duration: 0.2), value: active)
        }
    }
}

private struct ItemDropDelegate: DropDelegate {
    let store: DockStore
    let target: DockItem
    let pinned: Bool
    @Binding var highlighted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.url]) || store.dragging != nil
    }

    func dropEntered(info: DropInfo) {
        if isInternalDrag(info, store) {
            guard pinned, let id = store.dragging, id != target.id else { return }
            store.reorder(id, before: target.id)
        } else if target.isApp {
            highlighted = true
        }
    }

    func dropExited(info: DropInfo) { highlighted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isInternalDrag(info, store) ? .move : .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        highlighted = false
        if isInternalDrag(info, store) {
            store.dragging = nil
            return true
        }
        let providers = info.itemProviders(for: [.url])
        if target.isApp {
            // Like the Dock: a file dropped on an app opens in that app.
            loadURLs(providers) { urls in store.open(urls.filter(\.isFileURL), with: target) }
        } else {
            loadURLs(providers) { store.add(urls: $0, before: pinned ? target.id : nil) }
        }
        return true
    }
}

// MARK: - Trash

private struct TrashView: View {
    @ObservedObject var store: DockStore
    @State private var targeted = false
    @State private var hover = false

    var body: some View {
        let config = store.config
        let size = CGFloat(config.iconSize)
        let scale: CGFloat = (config.magnify && hover) || targeted ? CGFloat(config.magnification) : 1
        let image = NSImage(named: store.trashIsFull ? NSImage.trashFullName : NSImage.trashEmptyName)
            ?? NSWorkspace.shared.icon(forFile: DockStore.trashURL.path)

        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .scaleEffect(scale, anchor: config.edge.anchor)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: scale)
            .overlay(alignment: config.edge.inwardAlignment) {
                if (hover && config.showLabels) || (targeted && store.dragging != nil) {
                    Bubble(text: store.dragging == nil ? "Корзина" : "Убрать из бара")
                        .outside(config.edge, distance: size * (scale - 1) + 8)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { NSWorkspace.shared.open(DockStore.trashURL) }
            .onDrop(of: [.url, .text], delegate: TrashDropDelegate(store: store, targeted: $targeted))
            .overlay(RightClickMenu { store.trashMenu() })
    }
}

private struct TrashDropDelegate: DropDelegate {
    let store: DockStore
    @Binding var targeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL]) || store.dragging != nil
    }

    func dropEntered(info: DropInfo) { targeted = true }

    func dropExited(info: DropInfo) { targeted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        if isInternalDrag(info, store), let id = store.dragging {
            // Dropping a bar icon on the trash removes it from the bar, the file stays.
            store.dragging = nil
            store.remove(id)
            NSSound(named: "Pop")?.play()
            return true
        }
        loadURLs(info.itemProviders(for: [.fileURL])) { store.moveToTrash($0) }
        return true
    }
}

// MARK: - Folder stacks

struct StackView: View {
    let folder: URL
    let close: () -> Void

    @State private var entries: [URL] = []

    private static let cell: CGFloat = 84
    private static let columns = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(FileManager.default.displayName(atPath: folder.path)).font(.headline)
                Spacer()
                Button("Открыть в Finder") {
                    NSWorkspace.shared.open(folder)
                    close()
                }
                .buttonStyle(.link)
            }
            .padding(12)

            Divider()

            if entries.isEmpty {
                Text("Папка пуста")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: 8), count: Self.columns),
                              spacing: 12) {
                        ForEach(entries, id: \.self) { url in
                            VStack(spacing: 4) {
                                Image(nsImage: IconCache.shared.icon(for: url.path))
                                    .resizable()
                                    .frame(width: 52, height: 52)
                                Text(FileManager.default.displayName(atPath: url.path))
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: Self.cell)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                NSWorkspace.shared.open(url)
                                close()
                            }
                            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        }
                    }
                    .padding(12)
                }
                .frame(height: min(440, CGFloat((entries.count + Self.columns - 1) / Self.columns) * 96 + 24))
            }
        }
        .frame(width: CGFloat(Self.columns) * Self.cell + CGFloat(Self.columns - 1) * 8 + 24)
        .onAppear { entries = Self.load(folder) }
    }

    /// Newest first, like the Dock's "date added" sorting.
    private static func load(_ folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.addedToDirectoryDateKey], options: [.skipsHiddenFiles])) ?? []
        func added(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate) ?? .distantPast
        }
        return Array(urls.sorted { added($0) > added($1) }.prefix(150))
    }
}
