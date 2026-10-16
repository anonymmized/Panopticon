import AppKit
import SwiftUI

private final class WindowQueryTicket {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

/// One on-demand query, off the UI thread. Moving to another app invalidates it.
final class WindowListService {
    typealias Reader = (NSRunningApplication, () -> Bool) -> Result<[AX.Window], AX.WindowError>
    private let queue = DispatchQueue(label: "Panopticon.windows", qos: .userInitiated)
    private var ticket: WindowQueryTicket?
    private let read: Reader
    init(read: @escaping Reader = { AX.windowList(of: $0, cancelled: $1) }) { self.read = read }
    func cancel() { ticket?.cancel(); ticket = nil }
    deinit { ticket?.cancel() }

    func load(_ app: NSRunningApplication, receive: @escaping (Result<[AX.Window], AX.WindowError>) -> Void) {
        cancel()
        let next = WindowQueryTicket()
        ticket = next
        let read = self.read
        queue.async {
            guard !next.isCancelled else { return }
            let result = read(app, { next.isCancelled })
            DispatchQueue.main.async {
                guard !next.isCancelled else { return }
                receive(result)
            }
        }
    }

    func focus(_ window: AX.Window, app: NSRunningApplication, receive: @escaping (Bool) -> Void) {
        app.unhide()
        app.activate(options: [])
        queue.async {
            let success = AX.focus(window, of: app)
            DispatchQueue.main.async { receive(success) }
        }
    }
}

final class WindowSwitcherState: ObservableObject {
    enum Phase { case loading, permission, ready, unavailable }
    @Published var phase: Phase = .loading
    @Published var windows: [AX.Window] = []
    @Published var error = false
    var name = ""
    var icon = NSImage()
}

struct WindowSwitcherView: View {
    @ObservedObject var state: WindowSwitcherState
    @ObservedObject var localization = Localization.shared
    var connect: () -> Void
    var retry: () -> Void
    var select: (Int) -> Void
    var openApp: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: state.icon).resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(L("Окна приложения")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if state.phase == .ready {
                    Text("\(state.windows.count)").font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(.primary.opacity(0.07), in: Capsule())
                }
            }.padding(14)
            Divider().padding(.horizontal, 12)
            Group {
                switch state.phase {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(L("Получаем список окон…")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).frame(height: 96)
                case .permission:
                    message(symbol: "hand.raised", title: L("Выбирай нужное окно"),
                        detail: L("Разреши Универсальный доступ, чтобы видеть названия окон и переключаться между ними."))
                    Button(L("Подключить Универсальный доступ…"), action: connect)
                        .buttonStyle(.borderedProminent).controlSize(.small).padding(.bottom, 16)
                case .unavailable:
                    message(symbol: "rectangle.badge.exclamationmark", title: L("Приложение не ответило"),
                        detail: L("Попробуй ещё раз или открой приложение целиком."))
                    Button(L("Повторить"), action: retry).controlSize(.small).padding(.bottom, 12)
                case .ready:
                    if state.windows.isEmpty {
                        message(symbol: "macwindow", title: L("Нет открытых окон"),
                            detail: L("Приложение запущено, но доступных окон сейчас нет."))
                    } else {
                        ScrollView {
                            VStack(spacing: 3) {
                                ForEach(Array(state.windows.enumerated()), id: \.offset) { index, window in
                                    WindowSwitcherRow(title: window.title.isEmpty ? L("Без названия") : window.title,
                                        minimized: window.minimized) { select(index) }
                                }
                            }.padding(7)
                        }.frame(height: CGFloat(min(6, state.windows.count)) * 53 + 14)
                    }
                }
            }
            if state.error {
                Text(L("Окно уже недоступно. Обнови список.")).font(.system(size: 11))
                    .foregroundStyle(.orange).padding(10)
            }
            Divider().padding(.horizontal, 12)
            HStack {
                Text(L("Переключение одним нажатием")).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if state.phase == .ready {
                    Button(action: retry) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help(L("Обновить список окон"))
                }
                Button(action: openApp) { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.plain).help(L("Открыть приложение"))
            }.padding(.horizontal, 15).padding(.vertical, 11)
        }.frame(maxWidth: .infinity).tint(.accentColor).environment(\.controlActiveState, .active)
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(18)
    }
}

private struct WindowSwitcherRow: View {
    let title: String
    let minimized: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: minimized ? "minus.rectangle" : "macwindow")
                    .font(.system(size: 17, weight: .regular)).foregroundStyle(hovered ? Color.accentColor : .secondary)
                    .frame(width: 34, height: 34).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(minimized ? L("Свёрнуто · нажми, чтобы восстановить") : L("Перейти к окну"))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if hovered { Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor) }
            }.padding(.horizontal, 9).frame(height: 50).contentShape(Rectangle())
                .background(hovered ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityLabel(title + (minimized ? L(" — свёрнуто") : ""))
    }
}

/// The preview is another nonactivating panel: merely hovering never takes focus.
final class WindowSwitcherController {
    let panel: BarPanel
    let state = WindowSwitcherState()
    private let model: BarModel
    private weak var bar: BarView?
    private let service = WindowListService()
    private var dwell: Timer?
    private var closeTimer: Timer?
    private var candidate: String?
    private var candidateSpace = ""
    private var suppressed: String?
    private var application: NSRunningApplication?
    private var anchor = NSRect.zero
    private var token = UUID()
    private var nextTrustCheck: TimeInterval = 0
    private let trusted: () -> Bool
    var isShown: Bool { panel.isVisible }

    init(model: BarModel, bar: BarView, trusted: @escaping () -> Bool = { AX.trusted }) {
        self.model = model; self.bar = bar; self.trusted = trusted
        panel = BarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false; panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let glass = NSVisualEffectView()
        glass.blendingMode = .behindWindow; glass.material = .popover; glass.state = .active
        glass.wantsLayer = true; glass.layer?.cornerRadius = 18; glass.layer?.masksToBounds = true
        let host = NSHostingView(rootView: WindowSwitcherView(state: state,
            connect: { [weak self] in self?.connect() }, retry: { [weak self] in self?.load() },
            select: { [weak self] in self?.select($0) }, openApp: { [weak self] in self?.openApp() }))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        glass.addSubview(host)
        panel.contentView = glass
    }

    deinit {
        dwell?.invalidate(); closeTimer?.invalidate()
        panel.permitsPresentation = false; panel.orderOut(nil)
    }

    func update(at point: NSPoint, permitted: Bool, dragging: Bool) {
        validateContext()
        guard permitted, model.showWindowSwitcher, let bar else { close(); return }
        if dragging {
            if !panel.frame.contains(point) { dismissUntilExit() }
            return
        }
        if isShown && panel.frame.insetBy(dx: -5, dy: -5).contains(point) {
            closeTimer?.invalidate(); closeTimer = nil
            recheckPermission()
            return
        }
        let local = bar.convert(bar.window?.convertPoint(fromScreen: point) ?? .zero, from: nil)
        let index = bar.hitItem(local)
        if let index, index < bar.displayItems.count, bar.frames[index].insetBy(dx: -4, dy: -6).contains(local),
            let app = model.runningApplication(for: bar.displayItems[index]), !app.isTerminated {
            let item = bar.displayItems[index]
            if suppressed != item.id { suppressed = nil }
            guard suppressed != item.id else { return }
            closeTimer?.invalidate(); closeTimer = nil
            anchor = bar.screenRect(bar.frames[index])
            if candidate == item.id {
                if application?.processIdentifier != app.processIdentifier { close() }
                else { recheckPermission(); return }
            }
            close()
            candidate = item.id; application = app
            candidateSpace = model.selectedSpaceID
            anchor = bar.screenRect(bar.frames[index])
            state.name = item.name; state.icon = item.icon
            let timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
                self?.dwell = nil
                self?.load()
            }
            dwell = timer; RunLoop.main.add(timer, forMode: .common)
        } else if retainsDock(at: point) {
            closeTimer?.invalidate(); closeTimer = nil
        } else {
            suppressed = nil
            dwell?.invalidate(); dwell = nil
            guard isShown else { close(); return }
            if closeTimer == nil {
                let timer = Timer(timeInterval: 0.2, repeats: false) { [weak self] _ in self?.close() }
                closeTimer = timer; RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    func retainsDock(at point: NSPoint) -> Bool {
        guard isShown else { return false }
        return anchor.union(panel.frame).insetBy(dx: 8, dy: 8).contains(point)
    }

    private func recheckPermission() {
        let now = ProcessInfo.processInfo.systemUptime
        guard isShown, state.phase == .permission, now >= nextTrustCheck else { return }
        nextTrustCheck = now + 1
        if trusted() { load() }
    }

    func mouseDown(at point: NSPoint) {
        if !isShown || !panel.frame.contains(point) { dismissUntilExit() }
    }

    func dismissUntilExit() { let previous = candidate; close(); suppressed = previous }

    func showExplicit(item: DockItem, anchor: NSRect) {
        close()
        guard let app = model.runningApplication(for: item) else { return }
        candidate = item.id; application = app; self.anchor = anchor
        candidateSpace = model.selectedSpaceID
        state.name = item.name; state.icon = item.icon
        load()
    }

    func validateContext() {
        guard let candidate else { return }
        if !model.showWindowSwitcher || !model.barVisible || candidateSpace != model.selectedSpaceID
            || application?.isTerminated == true || !model.items.contains(where: { $0.id == candidate }) {
            dismissUntilExit()
        }
    }

    private func load() {
        guard let app = application, !app.isTerminated else { close(); return }
        service.cancel(); token = UUID()
        state.error = false; state.windows = []
        state.phase = trusted() ? .loading : .permission
        show()
        guard trusted() else { return }
        let request = token
        service.load(app) { [weak self] result in
            guard let self, self.token == request, self.isShown, !app.isTerminated else { return }
            switch result {
            case .success(let windows): self.state.windows = windows; self.state.phase = .ready
            case .failure(let error): self.state.phase = error == .permission ? .permission : .unavailable
            }
            self.show()
        }
    }

    private func connect() {
        AX.requestTrust()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        dismissUntilExit()
    }

    private func select(_ index: Int) {
        guard let app = application, !app.isTerminated, state.windows.indices.contains(index) else { load(); return }
        let window = state.windows[index]
        let request = token
        service.focus(window, app: app) { [weak self] success in
            guard let self, self.token == request else { return }
            if success { self.dismissUntilExit() }
            else { self.state.error = true; self.show() }
        }
    }

    private func openApp() {
        if let url = application?.bundleURL { ActionRouter.open(.application(url)) }
        else { application?.unhide(); application?.activate(options: []) }
        dismissUntilExit()
    }

    private func show() {
        let height: CGFloat
        switch state.phase {
        case .loading: height = 192
        case .permission: height = 278
        case .unavailable: height = 268
        case .ready: height = state.windows.isEmpty ? 235 : 110 + CGFloat(min(6, state.windows.count)) * 53
        }
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        guard let screen else { return }
        let frame = Self.frame(anchor: anchor, size: NSSize(width: 340, height: height + (state.error ? 40 : 0)),
            edge: model.dockEdge, visible: screen.visibleFrame)
        panel.appearance = model.dockTheme.appearance ?? NSApp.effectiveAppearance
        panel.title = L("Окна приложения") + " · " + state.name
        panel.setFrame(frame, display: true)
        panel.contentView?.subviews.first?.frame = NSRect(origin: .zero, size: frame.size)
        panel.permitsPresentation = true; panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
    }

    static func frame(anchor: NSRect, size: NSSize, edge: DockEdge, visible: NSRect) -> NSRect {
        let area = visible.insetBy(dx: min(12, visible.width / 4), dy: min(12, visible.height / 4))
        let width = min(size.width, area.width), height = min(size.height, area.height)
        var x = anchor.midX - width / 2, y = anchor.midY - height / 2
        switch edge {
        case .bottom: y = anchor.maxY + 10
        case .top: y = anchor.minY - height - 10
        case .left: x = anchor.maxX + 10
        case .right: x = anchor.minX - width - 10
        }
        return NSRect(x: min(max(x, area.minX), area.maxX - width),
            y: min(max(y, area.minY), area.maxY - height), width: width, height: height)
    }

    func close() {
        guard candidate != nil || application != nil || isShown || dwell != nil || closeTimer != nil else { return }
        dwell?.invalidate(); dwell = nil
        closeTimer?.invalidate(); closeTimer = nil
        service.cancel(); token = UUID()
        candidate = nil; application = nil
        state.windows = []
        panel.permitsPresentation = false; panel.orderOut(nil); panel.ignoresMouseEvents = true
    }
}
