import AppKit

final class BarAccessibilityButton: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return true }
}

final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
}

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class BarView: NSView, NSDraggingSource {
    let model: BarModel
    let music: MusicController
    let focus: FocusTimer
    let agenda: CalendarController
    var openAgenda: ((NSRect) -> Void)?
    var openCollection: ((AppCollection, NSRect) -> Void)?
    var openSettings: (() -> Void)?
    var openMusic: ((NSRect) -> Void)?
    let glass = NSVisualEffectView()
    private var tracking: NSTrackingArea?
    private var pointer: NSPoint?
    private var frames: [NSRect] = []
    private var sizes: [CGFloat] = []
    private var animation: Timer?
    private var downPoint: NSPoint?
    private var downIndex: Int?
    private var dropTarget: Int?
    private var insertion: Int?
    private var draggedID: String?
    private var icons: [String: NSImage] = [:]
    private(set) var barRect: NSRect = .zero
    private var widgetRect: NSRect = .zero
    private var widgetFrames: [NSRect] = []
    private var linkFrames: [NSRect] = []
    private var collectionFrames: [NSRect] = []
    private var launchTime: Date?
    private var launchID: String?
    private var settingsRect: NSRect = .zero
    private var step: CGFloat { CGFloat(model.iconSize + model.iconSpacing) }
    private var widgetWidth: CGFloat { model.widgetKinds.isEmpty ? 0 : (model.widgetStyle == "compact" ? CGFloat(model.iconSize + 4) : CGFloat(model.widgetWidth)) }
    private var widgetTotalWidth: CGFloat { CGFloat(model.widgetKinds.count) * widgetWidth + CGFloat(max(0, model.widgetKinds.count - 1)) * 8 }
    private var motionReduced: Bool { model.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var preferredWidth: CGFloat { CGFloat(model.items.count + model.collections.count + model.quickLinks.count) * step + widgetTotalWidth + (widgetWidth > 0 ? 12 : 0) + (model.showSettingsButton ? 50 : 24) }
    var preferredHeight: CGFloat { CGFloat(model.iconSize) * CGFloat(model.magnification) + CGFloat(model.hoverLift) + 48 }

    init(model: BarModel, music: MusicController, focus: FocusTimer, agenda: CalendarController) {
        self.model = model; self.music = music; self.focus = focus; self.agenda = agenda
        super.init(frame: .zero)
        wantsLayer = true
        glass.blendingMode = .behindWindow; glass.state = .active; glass.material = .hudWindow
        glass.wantsLayer = true; glass.layer?.cornerRadius = 24; glass.layer?.masksToBounds = true
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("app.newmacbar.item")])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("NewMacBar — панель приложений")

    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { animation?.invalidate() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) { pointer = convert(event.locationInWindow, from: nil); startAnimation(); needsDisplay = true }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { pointer = nil; startAnimation(); needsDisplay = true }
    func refresh() {
        glass.appearance = NSAppearance(named: model.theme == "light" ? .aqua : .darkAqua)
        appearance = NSAppearance(named: model.theme == "light" ? .aqua : .darkAqua)
        sizes = Array(repeating: CGFloat(model.iconSize), count: model.items.count)
        layoutIcons(); updateAccessibility(); needsDisplay = true
    }
    private func updateAccessibility() {
        var elements: [BarAccessibilityButton] = []
        for (index, item) in model.items.enumerated() where index < frames.count {
            let element = BarAccessibilityButton()
            element.setAccessibilityRole(.button); element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(item.name + (model.isRunning(item) ? " — запущено" : ""))
            element.setAccessibilityParent(self)
            element.setAccessibilityFrame(window?.convertToScreen(convert(frames[index], to: nil)) ?? frames[index])
            element.press = { [weak self] in self?.activate(item) }
            elements.append(element)
        }
        let settings = BarAccessibilityButton()
        settings.setAccessibilityRole(.button); settings.setAccessibilityEnabled(true); settings.setAccessibilityLabel("Настройки NewMacBar")
        settings.setAccessibilityParent(self)
        settings.setAccessibilityFrame(window?.convertToScreen(convert(settingsRect, to: nil)) ?? settingsRect)
        settings.press = { [weak self] in self?.openSettings?() }
        if model.showSettingsButton { elements.append(settings) }
        for (index, collection) in model.collections.enumerated() where index < collectionFrames.count {
            let element = BarAccessibilityButton(); element.setAccessibilityRole(.button); element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel("Коллекция " + collection.name); element.setAccessibilityParent(self)
            element.setAccessibilityFrame(window?.convertToScreen(convert(collectionFrames[index], to: nil)) ?? collectionFrames[index])
            element.press = { [weak self] in guard let self else { return }; self.openCollection?(collection, self.collectionFrames[index]) }
            elements.append(element)
        }
        for (index, link) in model.quickLinks.enumerated() where index < linkFrames.count {
            let element = BarAccessibilityButton(); element.setAccessibilityRole(.button); element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(link.name); element.setAccessibilityParent(self)
            element.setAccessibilityFrame(window?.convertToScreen(convert(linkFrames[index], to: nil)) ?? linkFrames[index])
            element.press = { if let url = link.url { ActionRouter.open(.resource(url)) } }; elements.append(element)
        }
        for (kind, rect) in zip(model.widgetKinds, widgetFrames) {
            let widget = BarAccessibilityButton(); widget.setAccessibilityRole(.button); widget.setAccessibilityEnabled(true)
            let label = ["music": "Открыть музыкальный плеер", "clock": "Часы", "calendar": "Календарь и события", "timer": "Таймер фокуса"][kind] ?? "Виджет"
            widget.setAccessibilityLabel(label); widget.setAccessibilityParent(self)
            widget.setAccessibilityFrame(window?.convertToScreen(convert(rect, to: nil)) ?? rect)
            widget.press = { [weak self] in self?.activateWidget(kind, rect: rect) }; elements.append(widget)
        }
        setAccessibilityChildren(elements)
    }
    override func layout() { super.layout(); layoutIcons() }
    private func layoutIcons() {
        let base = CGFloat(model.iconSize)
        let naturalWidth = preferredWidth
        let fit = min(1, (bounds.width - 8) / max(naturalWidth, 1))
        let barWidth = naturalWidth * fit
        barRect = NSRect(x: (bounds.width - barWidth) / 2, y: 5, width: barWidth, height: (base + 18) * fit)
        glass.frame = barRect
        glass.layer?.cornerRadius = CGFloat(model.cornerRadius)
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(model.theme == "light" ? 0.45 : 0.18).cgColor
        glass.layer?.backgroundColor = (model.theme == "light" ? NSColor.white : NSColor.black).withAlphaComponent(model.opacity).cgColor
        let items = model.items
        if sizes.count != items.count { sizes = Array(repeating: base, count: items.count) }
        frames = items.indices.map { i in
            let centerX = barRect.minX + (12 + base / 2 + CGFloat(i) * step) * fit
            let size = sizes[i] * fit
            let lift = model.hoverStyle == "lift" ? (size / max(base * fit, 1) - 1) * CGFloat(model.hoverLift) * 2 : 0
            return NSRect(x: centerX - size / 2, y: barRect.minY + 10 * fit + lift, width: size, height: size)
        }
        collectionFrames = model.collections.indices.map { i in NSRect(x: barRect.minX + (12 + CGFloat(items.count + i) * step) * fit, y: barRect.minY + 10 * fit, width: base * fit, height: base * fit) }
        linkFrames = model.quickLinks.indices.map { i in NSRect(x: barRect.minX + (12 + CGFloat(items.count + model.collections.count + i) * step) * fit, y: barRect.minY + 10 * fit, width: base * fit, height: base * fit) }
        let widgetX = barRect.minX + (CGFloat(items.count + model.collections.count + model.quickLinks.count) * step + 16) * fit
        widgetFrames = model.widgetKinds.indices.map { i in NSRect(x: widgetX + CGFloat(i) * (widgetWidth + 8) * fit, y: barRect.minY + 7 * fit, width: widgetWidth * fit, height: (base + 4) * fit) }
        widgetRect = widgetFrames.first ?? .zero
        settingsRect = NSRect(x: barRect.maxX - 34 * fit, y: barRect.midY - 12 * fit, width: 24 * fit, height: 24 * fit)
    }
    private func startAnimation() {
        guard animation == nil else { return }
        animation = Timer.scheduledTimer(withTimeInterval: ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 30 : 1.0 / 60, repeats: true) { [weak self] _ in self?.animate() }
        animation?.tolerance = 0.002
    }
    private func animate() {
        guard window != nil else { return }
        let base = CGFloat(model.iconSize)
        var changed = false
        for i in sizes.indices where i < frames.count {
            let distance = pointer.map { abs($0.x - frames[i].midX) } ?? 10000
            let influence = max(0, 1 - distance / (step * 1.6))
            let inside = pointer.map { $0.y < barRect.maxY + 28 && $0.y >= barRect.minY } ?? false
            let target = base * (1 + ((model.hoverStyle == "none" || motionReduced) ? 0 : 1) * (CGFloat(model.magnification) - 1) * influence * influence * (inside ? 1 : 0))
            if abs(sizes[i] - target) > 0.05 { sizes[i] += (target - sizes[i]) * 0.23; changed = true }
        }
        if let launchTime {
            if Date().timeIntervalSince(launchTime) > 0.7 { self.launchTime = nil; launchID = nil }
            changed = true
        }
        if changed { layoutIcons(); needsDisplay = true }
        else { animation?.invalidate(); animation = nil }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let items = model.items
        let foreground: NSColor = model.theme == "light" ? .black : .white
        for (i, item) in items.enumerated() where i < frames.count {
            let image = icons[item.id] ?? item.icon
            icons[item.id] = image
            var frame = frames[i]
            if item.id == launchID, let launchTime {
                let t = Date().timeIntervalSince(launchTime) / 0.7
                if model.launchStyle == "bounce" { frame.origin.y += CGFloat(abs(sin(t * .pi * 2)) * (1 - t) * 17) }
                if model.launchStyle == "pulse" { frame = frame.insetBy(dx: -CGFloat(sin(t * .pi) * 4), dy: -CGFloat(sin(t * .pi) * 4)) }
            }
            if dropTarget == i || (model.hoverGlow && pointer.map { frames[i].insetBy(dx: -4, dy: -4).contains($0) } == true) {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow(); shadow.shadowColor = accentColor.withAlphaComponent(0.65); shadow.shadowBlurRadius = 16; shadow.shadowOffset = .zero; shadow.set()
                accentColor.withAlphaComponent(0.09).setFill(); NSBezierPath(roundedRect: frame.insetBy(dx: 3, dy: 3), xRadius: 10, yRadius: 10).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: draggedID == item.id ? 0.4 : 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            if model.isRunning(item), model.indicatorStyle != "none" {
                let active = model.activeBundleID == item.bundleID
                (active ? accentColor : foreground.withAlphaComponent(0.7)).setFill()
                let width: CGFloat = model.indicatorStyle == "dash" ? 10 : 3.5
                NSBezierPath(roundedRect: NSRect(x: frames[i].midX - width / 2, y: barRect.minY + 3, width: width, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
        for (index, collection) in model.collections.enumerated() where index < collectionFrames.count {
            let rect = collectionFrames[index]
            foreground.withAlphaComponent(0.07).setFill(); NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            let apps = collection.items
            if apps.isEmpty { drawSymbol(collection.symbol, in: rect.insetBy(dx: 9, dy: 9), color: accentColor) }
            for (i, item) in apps.prefix(4).enumerated() {
                let side = rect.width * 0.35
                item.icon.draw(in: NSRect(x: rect.minX + 4 + CGFloat(i % 2) * (side + 3), y: rect.maxY - side - 4 - CGFloat(i / 2) * (side + 3), width: side, height: side))
            }
        }
        for (index, link) in model.quickLinks.enumerated() where index < linkFrames.count {
            let rect = linkFrames[index]
            accentColor.withAlphaComponent(0.1).setFill(); NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            drawSymbol(link.symbol, in: rect.insetBy(dx: 8, dy: 8), color: accentColor)
        }
        if model.showSeparator, widgetWidth > 0 {
            foreground.withAlphaComponent(0.13).setFill()
            NSBezierPath(rect: NSRect(x: widgetRect.minX - 7, y: barRect.minY + 13, width: 0.6, height: barRect.height - 26)).fill()
        }
        for (kind, rect) in zip(model.widgetKinds, widgetFrames) { drawWidget(foreground, kind: kind, rect: rect) }
        if model.showSettingsButton { drawSymbol("slider.horizontal.3", in: settingsRect.insetBy(dx: 4, dy: 4), color: foreground.withAlphaComponent(0.5)) }
        if model.showLabels, let point = pointer, let index = hitItem(point), index < items.count, draggedID == nil {
            let name = items[index].name
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: foreground]
            let width = (name as NSString).size(withAttributes: attributes).width + 22
            let x = min(max(frames[index].midX - width / 2, 2), bounds.width - width - 2)
            let labelRect = NSRect(x: x, y: min(frames[index].maxY + 9, bounds.height - 29), width: width, height: 25)
            (model.theme == "light" ? NSColor.white : NSColor(white: 0.14, alpha: 0.95)).setFill()
            NSBezierPath(roundedRect: labelRect, xRadius: 9, yRadius: 9).fill()
            drawText(name, in: labelRect.insetBy(dx: 11, dy: 6), font: .systemFont(ofSize: 11, weight: .medium), color: foreground)
        }
        if model.showLabels, let pointer, let index = linkFrames.firstIndex(where: { $0.contains(pointer) }), index < model.quickLinks.count {
            let name = model.quickLinks[index].name
            let width = min(CGFloat(name.count * 7 + 22), bounds.width - 4)
            let rect = NSRect(x: min(max(linkFrames[index].midX - width / 2, 2), bounds.width - width - 2), y: barRect.maxY + 8, width: width, height: 24)
            NSColor(white: 0.12, alpha: 0.95).setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            drawText(name, in: rect.insetBy(dx: 11, dy: 5), font: .systemFont(ofSize: 11, weight: .medium), color: .white)
        }
        if let insertion {
            let x = insertion < frames.count ? frames[insertion].midX - step / 2 : (frames.last?.midX ?? barRect.minX) + step / 2
            NSColor.systemTeal.setFill()
            NSBezierPath(roundedRect: NSRect(x: x - 1.5, y: barRect.minY + 10, width: 3, height: barRect.height - 20), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
    var accentColor: NSColor { ["violet": NSColor.systemPurple, "cyan": .systemCyan, "mint": .systemMint, "blue": .systemBlue, "orange": .systemOrange, "rose": .systemPink, "neutral": .gray][model.widgetAccent] ?? .systemPurple }
    private func drawWidget(_ foreground: NSColor, kind: String, rect: NSRect) {
        guard widgetWidth > 0 else { return }
        accentColor.withAlphaComponent(model.widgetOpacity).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11).fill()
        let compact = model.widgetStyle == "compact"
        let r = rect
        if compact {
            if kind == "music", let image = music.artwork { NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect: r.insetBy(dx: 3, dy: 3), xRadius: 8, yRadius: 8).addClip(); image.draw(in: r.insetBy(dx: 3, dy: 3)); NSGraphicsContext.restoreGraphicsState() }
            else { drawSymbol(kind == "music" ? "music.note" : (kind == "timer" ? "timer" : (kind == "calendar" ? "calendar" : "clock")), in: r.insetBy(dx: 10, dy: 10), color: foreground) }
            return
        }
        if kind == "calendar" {
            let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d"
            drawText(f.string(from: Date()), in: NSRect(x: r.minX + 10, y: r.minY + 4, width: 30, height: 28), font: .systemFont(ofSize: 25, weight: .semibold), color: foreground)
            let next = agenda.nextEvent
            drawText(next?.title ?? "Твой календарь", in: NSRect(x: r.minX + 46, y: r.midY, width: r.width - 52, height: 15), font: .systemFont(ofSize: 9, weight: .semibold), color: foreground)
            f.dateFormat = "EEE, d MMM"
            drawText(next.map { $0.time + " · " + $0.calendar } ?? f.string(from: Date()), in: NSRect(x: r.minX + 46, y: r.minY + 6, width: r.width - 52, height: 12), font: .systemFont(ofSize: 7.5), color: foreground.withAlphaComponent(0.6))
        } else if kind == "clock" {
            let time = DateFormatter(); time.dateFormat = (model.clockFormat == "12h" ? "h:mm" : "HH:mm") + (model.clockSeconds ? ":ss" : "") + (model.clockFormat == "12h" ? " a" : "")
            let date = DateFormatter(); date.locale = Locale(identifier: "ru_RU"); date.dateFormat = "EEEE, d MMM"
            drawText(time.string(from: Date()), in: NSRect(x: r.minX + 13, y: r.midY - 1, width: r.width - 22, height: 21), font: .monospacedDigitSystemFont(ofSize: model.clockSeconds ? 16 : 18, weight: .semibold), color: foreground)
            drawText(date.string(from: Date()).capitalized, in: NSRect(x: r.minX + 13, y: r.minY + 5, width: r.width - 18, height: 12), font: .systemFont(ofSize: 8.5, weight: .medium), color: foreground.withAlphaComponent(0.6))
        } else if kind == "timer" {
            drawSymbol(focus.isRunning ? "pause.circle.fill" : "play.circle.fill", in: NSRect(x: r.minX + 11, y: r.midY - 11, width: 22, height: 22), color: foreground)
            drawText(focus.text, in: NSRect(x: r.minX + 43, y: r.midY - 1, width: r.width - 48, height: 20), font: .monospacedDigitSystemFont(ofSize: 18, weight: .semibold), color: foreground)
            drawText(focus.isRunning ? "Время для фокуса" : "Нажми, чтобы начать", in: NSRect(x: r.minX + 43, y: r.minY + 5, width: r.width - 48, height: 12), font: .systemFont(ofSize: 8), color: foreground.withAlphaComponent(0.6))
        } else {
            let art = NSRect(x: r.minX + 6, y: r.minY + 6, width: r.height - 12, height: r.height - 12)
            if let image = music.artwork { NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect: art, xRadius: 7, yRadius: 7).addClip(); image.draw(in: art); NSGraphicsContext.restoreGraphicsState() }
            else { foreground.withAlphaComponent(0.08).setFill(); NSBezierPath(roundedRect: art, xRadius: 7, yRadius: 7).fill(); drawSymbol("music.note", in: art.insetBy(dx: 8, dy: 8), color: foreground) }
            let x = art.maxX + 8
            drawText(music.title, in: NSRect(x: x, y: r.maxY - 16, width: r.maxX - x - 7, height: 12), font: .systemFont(ofSize: 9, weight: .semibold), color: foreground)
            drawText(music.artist, in: NSRect(x: x, y: r.maxY - 27, width: r.maxX - x - 7, height: 11), font: .systemFont(ofSize: 7.5), color: foreground.withAlphaComponent(0.6))
            for (j, symbol) in ["backward.fill", music.playing ? "pause.fill" : "play.fill", "forward.fill"].enumerated() { drawSymbol(symbol, in: NSRect(x: r.maxX - 64 + CGFloat(j) * 21, y: r.minY + 5, width: 10, height: 9), color: foreground) }
        }
    }
    private func activate(_ item: DockItem) {
        if !motionReduced && model.launchStyle != "none" { launchTime = Date(); launchID = item.id; startAnimation() }
        model.launch(item)
    }
    private func activateWidget(_ kind: String, rect: NSRect) {
        switch kind {
        case "music": openMusic?(rect)
        case "calendar": openAgenda?(rect)
        case "timer": focus.toggle(minutes: model.timerMinutes)
        default: if model.clockAction == "agenda" { openAgenda?(rect) } else { model.openCalendar() }
        }
    }
    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
    private func drawSymbol(_ name: String, in rect: NSRect, color: NSColor) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [color])) else { return }
        image.draw(in: rect)
    }
    private func hitItem(_ point: NSPoint) -> Int? { frames.indices.first { frames[$0].insetBy(dx: -4, dy: -6).contains(point) } }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return barRect.contains(local) || frames.contains(where: { $0.contains(local) }) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil); downIndex = downPoint.flatMap(hitItem)
    }
    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil; downIndex = nil }
        let point = convert(event.locationInWindow, from: nil)
        if let index = downIndex, index == hitItem(point), index < model.items.count { activate(model.items[index]); return }
        if model.showSettingsButton && settingsRect.insetBy(dx: -5, dy: -10).contains(point) { openSettings?(); return }
        if let index = collectionFrames.firstIndex(where: { $0.contains(point) }), index < model.collections.count { openCollection?(model.collections[index], collectionFrames[index]); return }
        if let index = linkFrames.firstIndex(where: { $0.contains(point) }), index < model.quickLinks.count {
            if let url = model.quickLinks[index].url { ActionRouter.open(.resource(url)) }; return
        }
        for (kind, rect) in zip(model.widgetKinds, widgetFrames) where rect.contains(point) {
            if kind == "music", model.widgetStyle != "compact", point.y <= rect.minY + 18, point.x >= rect.maxX - 70 {
                let x = point.x - (rect.maxX - 64); music.command(x < 17 ? "previous track" : (x > 37 ? "next track" : "playpause"))
            } else { activateWidget(kind, rect: rect) }
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint, let index = downIndex, index < model.items.count else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - downPoint.x, point.y - downPoint.y) > 5, draggedID == nil else { return }
        let item = model.items[index]
        guard model.pinned.contains(item) else { return }
        let pasteboard = NSPasteboardItem(); pasteboard.setString(item.id, forType: NSPasteboard.PasteboardType("app.newmacbar.item"))
        let drag = NSDraggingItem(pasteboardWriter: pasteboard)
        drag.setDraggingFrame(frames[index], contents: item.icon)
        draggedID = item.id; pointer = nil
        beginDraggingSession(with: [drag], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { draggedID = nil; insertion = nil; dropTarget = nil; downIndex = nil; downPoint = nil; needsDisplay = true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let internalDrag = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("app.newmacbar.item")) != nil
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !internalDrag && urls.contains(where: { $0.pathExtension.lowercased() != "app" }), let index = hitItem(point) {
            dropTarget = index; insertion = nil; needsDisplay = true; return .copy
        }
        dropTarget = nil
        insertion = min(frames.firstIndex(where: { point.x < $0.midX }) ?? frames.count, model.pinned.count)
        needsDisplay = true
        return internalDrag ? .move : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { insertion = nil; dropTarget = nil; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let boundary = insertion ?? model.pinned.count
        defer { insertion = nil; dropTarget = nil; needsDisplay = true }
        if let id = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("app.newmacbar.item")) { model.move(id, to: boundary); return true }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        if let index = dropTarget, index < model.items.count {
            NSWorkspace.shared.open(urls, withApplicationAt: model.items[index].url, configuration: .init()) { _, error in
                if let error { DispatchQueue.main.async { ActionRouter.showError(error.localizedDescription) } }
            }
            return true
        }
        var accepted = false
        for (offset, url) in urls.enumerated() {
            if url.pathExtension.lowercased() == "app" { model.add(url, at: boundary + offset); accepted = true }
            else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { accepted = model.addQuickLink(name: FileManager.default.displayName(atPath: url.path), kind: "folder", destination: url.path) || accepted }
        }
        return accepted
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let point = convert(event.locationInWindow, from: nil)
        if let index = hitItem(point), index < model.items.count {
            let item = model.items[index]
            addMenu(menu, item.name, #selector(openItem(_:)), item)
            addMenu(menu, model.pinned.contains(item) ? "Убрать из закреплённых" : "Закрепить в панели", #selector(pinItem(_:)), item)
            addMenu(menu, "Показать в Finder", #selector(revealItem(_:)), item)
            if model.isRunning(item), item.bundleID != "com.apple.finder" { addMenu(menu, "Завершить приложение", #selector(quitItem(_:)), item) }
            menu.addItem(.separator())
        }
        if zip(model.widgetKinds, widgetFrames).contains(where: { $0.0 == "timer" && $0.1.contains(point) }) { addMenu(menu, "Сбросить таймер", #selector(resetTimer(_:)), nil); menu.addItem(.separator()) }
        addMenu(menu, "Открыть выбранный календарь", #selector(calendarAction(_:)), nil)
        addMenu(menu, "Настройки NewMacBar…", #selector(settingsAction(_:)), nil)
        addMenu(menu, "Завершить NewMacBar", #selector(quitBar(_:)), nil)
        return menu
    }
    private func addMenu(_ menu: NSMenu, _ title: String, _ action: Selector, _ item: DockItem?) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; entry.representedObject = item; menu.addItem(entry)
    }
    @objc private func openItem(_ sender: NSMenuItem) { if let item = sender.representedObject as? DockItem { model.launch(item) } }
    @objc private func pinItem(_ sender: NSMenuItem) { if let item = sender.representedObject as? DockItem { model.pinned.contains(item) ? model.remove(item) : model.add(item.url) } }
    @objc private func revealItem(_ sender: NSMenuItem) { if let item = sender.representedObject as? DockItem { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } }
    @objc private func quitItem(_ sender: NSMenuItem) { if let item = sender.representedObject as? DockItem { model.running.first { $0.bundleIdentifier == item.bundleID }?.terminate() } }
    @objc private func calendarAction(_ sender: Any?) { model.openCalendar() }
    @objc private func resetTimer(_ sender: Any?) { focus.reset(minutes: model.timerMinutes) }
    @objc private func settingsAction(_ sender: Any?) { openSettings?() }
    @objc private func quitBar(_ sender: Any?) { NSApp.terminate(nil) }
}
