import AppKit
import ApplicationServices
import SwiftUI

/// Render actual product components with disposable demo preferences. No network,
/// permission prompts, user documents or system Dock changes are involved.
func renderDocumentationAssets() {
    _ = NSApplication.shared
    let suite = "app.panopticon.docs.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let previous = Localization.shared
    defer { defaults.removePersistentDomain(forName: suite); Localization.shared = previous }
    Localization.shared = Localization(defaults: defaults)
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("docs/assets", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in [AppLanguage.english, .russian] {
            Localization.shared.setLanguage(language)
            let russian = language == .russian
            let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")?.resolvingSymlinksInPath().path ?? "/Applications/Safari.app"
            defaults.set([
                "/System/Library/CoreServices/Finder.app", safari,
                "/System/Applications/Notes.app", "/System/Applications/Calendar.app",
                "/System/Applications/Music.app", "/System/Applications/Reminders.app",
            ], forKey: "pinned")
            let model = BarModel(defaults: defaults, observe: false, systemDockProvider: { [] })
            model.batch {
                model.applyNativeDockStyle(); model.theme = "electric"; model.opacity = 0.22
                model.showRunning = false; model.showSpaces = false; model.replaceDock = false
                model.widget = "clock"; model.secondaryWidget = "timer"; model.widgetAccent = "violet"
                model.widgetWidth = 190; model.motionMode = "reduced"; model.iconSize = 48
                model.showSettingsButton = false
            }
            let focus = FocusTimer(defaults: defaults)
            focus.reset(minutes: 25); focus.soundEnabled = false
            let agenda = CalendarController()
            let music = MusicController()
            let bar = BarView(model: model, music: music, focus: focus, agenda: agenda)
            let hero = DocumentationCanvas(russian: russian)
            let window = NSWindow(contentRect: hero.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hero
            bar.availableLength = 1280
            let panelContainer = NSView(frame: NSRect(x: (hero.bounds.width - bar.preferredWidth) / 2, y: 112,
                width: bar.preferredWidth, height: bar.preferredHeight))
            bar.frame = NSRect(x: 0, y: 0,
                width: bar.preferredWidth, height: bar.preferredHeight)
            hero.addSubview(panelContainer)
            panelContainer.addSubview(bar.surfaceShadow); panelContainer.addSubview(bar.glass); panelContainer.addSubview(bar)
            bar.refresh()
            try saveDocumentationView(hero, window: window, to: output.appendingPathComponent("hero-\(language.rawValue).png"))
            window.close()

            let ui = UIStateStore(defaults: defaults); ui.appearance = "dark"
            let settings = SettingsView(model: model,
                dock: DockIntegration(defaults: defaults, readDomain: { [:] }, execute: { _, _ in CommandResult(status: 0, output: "") }),
                focus: focus, catalog: AppCatalog(), agenda: agenda, ui: ui)
            let settingsContent = VStack(alignment: .leading, spacing: 20) {
                Text(russian ? "Настрой под себя." : "Make it yours.").font(.system(size: 30, weight: .semibold))
                Text(russian ? "Размер, характер движения и восемь тем стекла." : "Size, motion and eight glass themes.")
                    .font(Studio.body).foregroundStyle(.secondary)
                DockPreview(model: model)
                ScrollView { settings.appearance }
            }.padding(32).frame(width: 840, height: 900)
                .background(Studio.canvas).preferredColorScheme(.dark)
                .environment(\.locale, Localization.shared.locale).tint(.purple)
            try saveDocumentationContent(settingsContent, size: NSSize(width: 840, height: 900),
                to: output.appendingPathComponent("appearance-\(language.rawValue).png"))

            let widgets = HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(russian ? "Время для себя." : "A little more focus.")
                        .font(.system(size: 26, weight: .semibold))
                    Text(russian ? "Таймер с сохранением сессии." : "A timer that remembers your session.")
                        .font(Studio.body).foregroundStyle(.secondary)
                    FocusPopoverView(focus: focus, model: model).frame(width: 340, height: 410)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text(russian ? "Свои инструменты." : "Your own tools.")
                        .font(.system(size: 26, weight: .semibold))
                    Text(russian ? "Выбирай приложение или веб-календарь." : "Choose any calendar app or website.")
                        .font(Studio.body).foregroundStyle(.secondary)
                    VStack(spacing: 24) {
                        MiniWidget(kind: "calendar", accent: .purple).scaleEffect(1.35).frame(height: 80)
                        MiniWidget(kind: "music", accent: .indigo).scaleEffect(1.35).frame(height: 80)
                        MiniWidget(kind: "clock", accent: .blue).scaleEffect(1.35).frame(height: 80)
                    }.frame(width: 340, height: 410).background(Studio.surface, in: RoundedRectangle(cornerRadius: 20))
                }
            }.padding(32).frame(width: 820, height: 570).background(Studio.canvas)
                .preferredColorScheme(.dark).environment(\.locale, Localization.shared.locale).tint(.purple)
            try saveDocumentationContent(widgets, size: NSSize(width: 820, height: 570),
                to: output.appendingPathComponent("widgets-\(language.rawValue).png"))

            let state = WindowSwitcherState()
            state.name = "Safari"
            state.icon = NSWorkspace.shared.icon(forFile: safari)
            state.phase = .ready
            // Static demo elements are never queried or acted on by this renderer.
            let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            state.windows = [
                AX.Window(title: "Panopticon · GitHub", minimized: false, element: element),
                AX.Window(title: russian ? "Идеи для проекта" : "Project ideas", minimized: false, element: element),
                AX.Window(title: russian ? "Календарь · Сегодня" : "Calendar · Today", minimized: true, element: element),
            ]
            let windows = HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(russian ? "Твоё окно. Сразу." : "Your window. Right here.")
                        .font(.system(size: 30, weight: .semibold))
                    Text(russian ? "Наведи. Выбери. Продолжай." : "Hover. Choose. Keep going.")
                        .font(.system(size: 17)).foregroundStyle(.secondary)
                    Label(russian ? "Свёрнутые окна тоже рядом" : "Minimized windows included", systemImage: "macwindow")
                    Label(russian ? "Фокус остаётся у тебя" : "Keyboard focus stays yours", systemImage: "cursorarrow")
                    Label(russian ? "Без записи экрана" : "No Screen Recording required", systemImage: "hand.raised")
                }.font(.system(size: 12)).frame(width: 370, alignment: .leading)
                WindowSwitcherView(state: state, connect: {}, retry: {}, select: { _ in }, openApp: {})
                    .frame(width: 340).background(Studio.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 28, y: 12)
            }.padding(40).frame(width: 900, height: 450).background(Studio.canvas)
                .preferredColorScheme(.dark).environment(\.locale, Localization.shared.locale).tint(.purple)
            try saveDocumentationContent(windows, size: NSSize(width: 900, height: 450),
                to: output.appendingPathComponent("windows-\(language.rawValue).png"))
        }
        print("PASS: bilingual documentation previews rendered from real app components")
    } catch {
        fputs("Documentation rendering failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

private func saveDocumentationContent<Content: View>(_ content: Content, size: NSSize, to url: URL) throws {
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: content); host.frame = NSRect(origin: .zero, size: size)
    window.contentView = host
    defer { window.close() }
    try saveDocumentationView(host, window: window, to: url)
}

private func saveDocumentationView(_ view: NSView, window: NSWindow, to url: URL) throws {
    window.orderFront(nil)
    view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url, options: .atomic)
}

private final class DocumentationCanvas: NSView {
    let russian: Bool
    init(russian: Bool) {
        self.russian = russian
        super.init(frame: NSRect(x: 0, y: 0, width: 1440, height: 780))
    }
    required init?(coder: NSCoder) { fatalError("Unsupported") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.035, green: 0.043, blue: 0.09, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 32, yRadius: 32).fill()
        for (rect, color) in [
            (NSRect(x: -140, y: -170, width: 1100, height: 750), NSColor.systemBlue),
            (NSRect(x: 600, y: -80, width: 1000, height: 900), NSColor.systemPurple),
        ] {
            NSGradient(starting: color.withAlphaComponent(0.34), ending: color.withAlphaComponent(0))?
                .draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
        }
        draw(russian ? "СОБСТВЕННОЕ ПРОСТРАНСТВО НА MAC" : "YOUR OWN SPACE ON MAC", y: 655, size: 13,
            weight: .semibold, color: NSColor(calibratedRed: 0.64, green: 0.68, blue: 1, alpha: 1), tracking: 4)
        draw("Panopticon", y: 525, size: 104, weight: .semibold, color: .white, tracking: -4)
        draw(russian ? "Нужное рядом. Остальное — в тишине." : "Keep what matters within reach.",
            y: 459, size: 28, weight: .regular, color: .white.withAlphaComponent(0.76))
        draw(russian ? "ПРИЛОЖЕНИЯ  /  ПРОСТРАНСТВА  /  ВИДЖЕТЫ" : "APPS  /  SPACES  /  WIDGETS",
            y: 376, size: 12, weight: .medium, color: .white.withAlphaComponent(0.5), tracking: 3)
        draw(russian ? "Нативно. Бесплатно. Без телеметрии." : "Native. Free. No telemetry.",
            y: 57, size: 15, weight: .medium, color: .white.withAlphaComponent(0.54))
    }
    private func draw(_ text: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor, tracking: CGFloat = 0) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        (text as NSString).draw(in: NSRect(x: 40, y: y, width: bounds.width - 80, height: size * 1.5),
            withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
                .paragraphStyle: style, .kern: tracking])
    }
}
