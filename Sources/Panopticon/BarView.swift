import AppKit

final class BarAccessibilityButton: NSAccessibilityElement {
    var frameProvider: (() -> NSRect)?
    override func accessibilityFrame() -> NSRect { frameProvider?() ?? super.accessibilityFrame() }
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { guard let press else { return false }; press(); return true }
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

    func updateMousePassthrough(for bar: BarView, at screenPoint: NSPoint) {
        let point = bar.convert(convertPoint(fromScreen: screenPoint), from: nil)
        let ignores = !bar.containsInteractivePoint(point)
        if ignoresMouseEvents != ignores { ignoresMouseEvents = ignores }
    }
}

final class BarView: NSView, NSDraggingSource {
    let model: BarModel
    let music: MusicController
    let focus: FocusTimer
    let agenda: CalendarController
    var openFolder: ((URL, NSRect) -> Void)?
    var openAgenda: ((NSRect) -> Void)?
    var openCollection: ((AppCollection, NSRect) -> Void)?
    var openSettings: (() -> Void)?
    var openMusic: ((NSRect) -> Void)?
    let glass = NSVisualEffectView()
    private var tracking: NSTrackingArea?
    private let surfaceTint = CAGradientLayer()
    private var spaceFrames: [NSRect] = []
    private var trashRect: NSRect = .zero
    private var scrollAccumulator: CGFloat = 0
    private var lastScrollSwitch = Date.distantPast
    private var pointer: NSPoint?
    private var frames: [NSRect] = []
    private var sizes: [CGFloat] = []
    private var animation: Timer?
    private var downPoint: NSPoint?
    private var downIndex: Int?
    private var dropTarget: Int?
    private var insertion: Int?
    private var draggedID: String?
    private var collectionIcons: [[NSImage]] = []
    private var lastItems: [String] = []
    private var lastBase: CGFloat = 0
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
    private var compactWidgets: Bool { model.widgetStyle == "compact" || model.dockEdge.isVertical }
    private var widgetWidth: CGFloat { model.widgetKinds.isEmpty ? 0 : (compactWidgets ? CGFloat(model.iconSize + 4) : CGFloat(model.widgetWidth)) }
    private var widgetTotalWidth: CGFloat { CGFloat(model.widgetKinds.count) * widgetWidth + CGFloat(max(0, model.widgetKinds.count - 1)) * 8 }
    private var motionReduced: Bool { model.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var spacesWidth: CGFloat { model.showSpaces ? CGFloat(model.spaces.count) * 29 + 8 : 0 }
    private var trashWidth: CGFloat { model.showTrash ? step + 8 : 0 }
    private var baseWidth: CGFloat { spacesWidth + trashWidth + CGFloat(model.items.count + model.collections.count + model.quickLinks.count) * step + widgetTotalWidth + (widgetWidth > 0 ? 12 : 0) + (model.showSettingsButton ? 50 : 24) }
    private var preferredLength: CGFloat { baseWidth + (motionReduced || model.hoverStyle == "none" || model.items.isEmpty ? 0 : CGFloat(model.iconSize * (model.magnification - 1) * 2.5)) }
    private var preferredThickness: CGFloat { CGFloat(model.iconSize) * CGFloat(model.magnification) + CGFloat(model.hoverLift) + 48 + (model.dockEdge.isVertical && model.showLabels ? 180 : 0) }

    var preferredWidth: CGFloat { model.dockEdge.isVertical ? preferredThickness : preferredLength }
    var preferredHeight: CGFloat { model.dockEdge.isVertical ? preferredLength : preferredThickness }

    init(model: BarModel, music: MusicController, focus: FocusTimer, agenda: CalendarController) {
        self.model = model; self.music = music; self.focus = focus; self.agenda = agenda
        super.init(frame: .zero)
        wantsLayer = true
        SiteIconCache.shared.onChange = { [weak self] in self?.needsDisplay = true }
        glass.blendingMode = .behindWindow; glass.state = .active; glass.material = .hudWindow
        glass.wantsLayer = true; glass.layer?.cornerRadius = 24; glass.layer?.masksToBounds = true
        surfaceTint.startPoint = CGPoint(x: 0, y: 0); surfaceTint.endPoint = CGPoint(x: 1, y: 1)
        glass.layer?.addSublayer(surfaceTint)
        registerForDraggedTypes([.fileURL, .URL, NSPasteboard.PasteboardType("app.panopticon.item")])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("Panopticon — панель приложений"))

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
        setAccessibilityLabel(L("Panopticon — панель приложений"))
        glass.appearance = model.dockTheme.appearance ?? NSApp.effectiveAppearance
        appearance = model.dockTheme.appearance ?? NSApp.effectiveAppearance
        let ids = model.items.map(\.id)
        if ids != lastItems || lastBase != CGFloat(model.iconSize) { sizes = Array(repeating: CGFloat(model.iconSize), count: model.items.count) }
        lastItems = ids; lastBase = CGFloat(model.iconSize)
        collectionIcons = model.collections.map { $0.items.prefix(4).map(\.icon) }
        layoutIcons(); updateAccessibility(); needsDisplay = true
    }
    private func updateAccessibility() {
        var elements: [BarAccessibilityButton] = []
        for (index, item) in model.items.enumerated() where index < frames.count {
            let element = BarAccessibilityButton()
            element.setAccessibilityRole(.button); element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(item.name + (model.isRunning(item) ? L(" — запущено") : ""))
            element.setAccessibilityParent(self)
            element.setAccessibilityFrame(window?.convertToScreen(convert(frames[index], to: nil)) ?? frames[index])
            element.frameProvider = { [weak self] in guard let self, index < self.frames.count else { return .zero }; return self.screenRect(self.frames[index]) }
            element.press = { [weak self] in self?.activate(item) }
            elements.append(element)
        }
        let settings = BarAccessibilityButton()
        settings.setAccessibilityRole(.button); settings.setAccessibilityEnabled(true); settings.setAccessibilityLabel(L("Настройки Panopticon"))
        settings.setAccessibilityParent(self)
        settings.setAccessibilityFrame(window?.convertToScreen(convert(settingsRect, to: nil)) ?? settingsRect)
        settings.frameProvider = { [weak self] in guard let self else { return .zero }; return self.screenRect(self.settingsRect) }
        settings.press = { [weak self] in self?.openSettings?() }
        if model.showSettingsButton { elements.append(settings) }
        for (index, collection) in model.collections.enumerated() where index < collectionFrames.count {
            let element = BarAccessibilityButton(); element.setAccessibilityRole(.button); element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(L("Коллекция ") + collection.name); element.setAccessibilityParent(self)
            element.setAccessibilityFrame(window?.convertToScreen(convert(collectionFrames[index], to: nil)) ?? collectionFrames[index])
            element.frameProvider = { [weak self] in guard let self, index < self.collectionFrames.count else { return .zero }; return self.screenRect(self.collectionFrames[index]) }
            element.press = { [weak self] in guard let self else { return }; self.openCollection?(collection, self.collectionFrames[index]) }
            elements.append(element)
        }
        for (index, link) in model.quickLinks.enumerated() where index < linkFrames.count {
            let element = BarAccessibilityButton(); element.setAccessibilityRole(.button); element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(link.name); element.setAccessibilityParent(self)
            element.setAccessibilityFrame(window?.convertToScreen(convert(linkFrames[index], to: nil)) ?? linkFrames[index])
            element.frameProvider = { [weak self] in guard let self, index < self.linkFrames.count else { return .zero }; return self.screenRect(self.linkFrames[index]) }
            element.press = { [weak self] in
                guard let self, index < self.linkFrames.count, let url = link.url else { return }
                if link.kind == "folder" { self.openFolder?(url, self.linkFrames[index]) } else { ActionRouter.open(.resource(url)) }
            }; elements.append(element)
        }
        for (kind, rect) in zip(model.widgetKinds, widgetFrames) {
            let widget = BarAccessibilityButton(); widget.setAccessibilityRole(.button); widget.setAccessibilityEnabled(true)
            let label = ["music": L("Открыть музыкальный плеер"), "clock": L("Часы"), "calendar": L("Календарь и события"), "timer": L("Таймер фокуса")][kind] ?? L("Виджет")
            widget.setAccessibilityLabel(label); widget.setAccessibilityParent(self)
            widget.setAccessibilityFrame(window?.convertToScreen(convert(rect, to: nil)) ?? rect)
            widget.frameProvider = { [weak self] in guard let self, let i = self.model.widgetKinds.firstIndex(of: kind), i < self.widgetFrames.count else { return .zero }; return self.screenRect(self.widgetFrames[i]) }
            widget.press = { [weak self] in guard let self, let i = self.model.widgetKinds.firstIndex(of: kind), i < self.widgetFrames.count else { return }; self.activateWidget(kind, rect: self.widgetFrames[i]) }; elements.append(widget)
        }
        for (index, space) in model.spaces.enumerated() where index < spaceFrames.count {
            let element = BarAccessibilityButton(); element.setAccessibilityRole(.button); element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(L("Пространство ") + space.name + (space.id == model.selectedSpaceID ? L(" — выбрано") : ""))
            element.setAccessibilityParent(self)
            element.frameProvider = { [weak self] in guard let self, index < self.spaceFrames.count else { return .zero }; return self.screenRect(self.spaceFrames[index]) }
            element.press = { [weak self] in self?.model.selectSpace(space.id) }; elements.append(element)
        }
        if model.showTrash {
            let trash = BarAccessibilityButton(); trash.setAccessibilityRole(.button); trash.setAccessibilityEnabled(true)
            trash.setAccessibilityLabel(L("Корзина")); trash.setAccessibilityParent(self)
            trash.frameProvider = { [weak self] in guard let self else { return .zero }; return self.screenRect(self.trashRect) }
            trash.press = { NSWorkspace.shared.open(BarModel.trashURL) }; elements.append(trash)
        }
        setAccessibilityChildren(elements)
    }
    private func screenRect(_ rect: NSRect) -> NSRect { window?.convertToScreen(convert(rect, to: nil)) ?? rect }
    override func layout() { super.layout(); layoutIcons() }
    private func orient(_ rect: NSRect) -> NSRect {
        switch model.dockEdge {
        case .bottom: return rect
        case .top: return NSRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        case .left: return NSRect(x: rect.minY, y: bounds.height - rect.maxX, width: rect.height, height: rect.width)
        case .right: return NSRect(x: bounds.width - rect.maxY, y: bounds.height - rect.maxX, width: rect.height, height: rect.width)
        }
    }
    private func axis(_ point: NSPoint) -> CGFloat { model.dockEdge.isVertical ? bounds.height - point.y : point.x }
    private func layoutIcons() {
        let base = CGFloat(model.iconSize)
        let items = model.items
        if sizes.count != items.count { sizes = Array(repeating: base, count: items.count) }
        let extra = sizes.reduce(0) { $0 + max(0, $1 - base) }
        let naturalWidth = baseWidth + extra
        let length = model.dockEdge.isVertical ? bounds.height : bounds.width
        let fit = max(0.05, min(1, (length - 8) / max(naturalWidth, 1)))
        let barWidth = naturalWidth * fit
        let canonical = NSRect(x: (length - barWidth) / 2, y: 5, width: barWidth, height: (base + 18) * fit)
        barRect = orient(canonical)
        glass.frame = barRect
        glass.layer?.cornerRadius = CGFloat(model.cornerRadius)
        glass.layer?.borderWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 2 : 1
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(model.dockTheme.isLight ? 0.45 : 0.18).cgColor
        glass.layer?.backgroundColor = (model.dockTheme.isLight ? NSColor.white : NSColor.black).withAlphaComponent(model.opacity).cgColor
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surfaceTint.frame = CGRect(origin: .zero, size: barRect.size)
        surfaceTint.colors = model.dockTheme.nsTint.map { $0.withAlphaComponent(max(0.12, model.opacity)).cgColor }
        surfaceTint.isHidden = model.dockTheme.nsTint.isEmpty
        CATransaction.commit()
        spaceFrames = model.showSpaces ? model.spaces.indices.map { i in
            orient(NSRect(x: canonical.minX + (10 + CGFloat(i) * 29) * fit, y: canonical.midY - 12 * fit, width: 24 * fit, height: 24 * fit))
        } : []
        frames = BarGeometry.frames(sizes: sizes, spacing: CGFloat(model.iconSpacing), origin: NSPoint(x: canonical.minX + (12 + spacesWidth) * fit, y: canonical.minY + 10 * fit), scale: fit, base: base, lift: model.hoverStyle == "lift" ? CGFloat(model.hoverLift) : 0).map(orient)
        let appEnd = sizes.reduce(CGFloat(12) + spacesWidth) { $0 + $1 + CGFloat(model.iconSpacing) }
        collectionFrames = model.collections.indices.map { i in orient(NSRect(x: canonical.minX + (appEnd + CGFloat(i) * step) * fit, y: canonical.minY + 10 * fit, width: base * fit, height: base * fit)) }
        linkFrames = model.quickLinks.indices.map { i in orient(NSRect(x: canonical.minX + (appEnd + CGFloat(model.collections.count + i) * step) * fit, y: canonical.minY + 10 * fit, width: base * fit, height: base * fit)) }
        let afterLinks = appEnd + CGFloat(model.collections.count + model.quickLinks.count) * step
        trashRect = model.showTrash ? orient(NSRect(x: canonical.minX + (afterLinks + 4) * fit, y: canonical.minY + 10 * fit, width: base * fit, height: base * fit)) : .zero
        let widgetX = canonical.minX + (afterLinks + trashWidth + 4) * fit
        widgetFrames = model.widgetKinds.indices.map { i in orient(NSRect(x: widgetX + CGFloat(i) * (widgetWidth + 8) * fit, y: canonical.minY + 7 * fit, width: widgetWidth * fit, height: (base + 4) * fit)) }
        widgetRect = widgetFrames.first ?? .zero
        settingsRect = orient(NSRect(x: canonical.maxX - 34 * fit, y: canonical.midY - 12 * fit, width: 24 * fit, height: 24 * fit))
    }
    private func startAnimation() {
        guard animation == nil else { return }
        animation = Timer.scheduledTimer(withTimeInterval: ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 30 : 1.0 / 60, repeats: true) { [weak self] _ in self?.animate() }
        animation?.tolerance = 0.002
    }
    private func animate() {
        guard window != nil else { animation?.invalidate(); animation = nil; return }
        let base = CGFloat(model.iconSize)
        var changed = false
        for i in sizes.indices where i < frames.count {
            let distance = pointer.map { abs(axis($0) - axis(NSPoint(x: frames[i].midX, y: frames[i].midY))) } ?? 10000
            let influence = max(0, 1 - distance / (step * 1.6))
            let inside = draggedID == nil && (pointer.map { barRect.insetBy(dx: -28, dy: -28).contains($0) } ?? false)
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
        let foreground: NSColor = model.dockTheme.isLight ? .black : .white
        for (i, item) in items.enumerated() where i < frames.count {
            let image = icons[item.id] ?? item.icon
            icons[item.id] = image
            var frame = frames[i]
            if item.id == launchID, let launchTime {
                let t = Date().timeIntervalSince(launchTime) / 0.7
                if model.launchStyle == "bounce" {
                    let amount = CGFloat(abs(sin(t * .pi * 2)) * (1 - t) * 17)
                    switch model.dockEdge { case .bottom: frame.origin.y += amount; case .top: frame.origin.y -= amount; case .left: frame.origin.x += amount; case .right: frame.origin.x -= amount }
                }
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
                let indicator: NSRect
                switch model.dockEdge {
                case .bottom: indicator = NSRect(x: frames[i].midX - width / 2, y: barRect.minY + 3, width: width, height: 3)
                case .top: indicator = NSRect(x: frames[i].midX - width / 2, y: barRect.maxY - 6, width: width, height: 3)
                case .left: indicator = NSRect(x: barRect.minX + 3, y: frames[i].midY - width / 2, width: 3, height: width)
                case .right: indicator = NSRect(x: barRect.maxX - 6, y: frames[i].midY - width / 2, width: 3, height: width)
                }
                NSBezierPath(roundedRect: indicator, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
        for (index, space) in model.spaces.enumerated() where index < spaceFrames.count {
            let rect = spaceFrames[index]
            let selected = space.id == model.selectedSpaceID
            (selected ? accentColor.withAlphaComponent(0.75) : foreground.withAlphaComponent(0.07)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            drawSymbol(space.symbol, in: rect.insetBy(dx: 6, dy: 6), color: selected ? .white : foreground.withAlphaComponent(0.65))
        }
        if model.showTrash { drawSymbol("trash", in: trashRect.insetBy(dx: 5, dy: 3), color: foreground.withAlphaComponent(0.7)) }
        for (index, item) in items.enumerated() where index < frames.count {
            if let badge = model.badge(for: item), !badge.isEmpty {
                let rect = NSRect(x: frames[index].maxX - 17, y: frames[index].maxY - 12, width: 22, height: 16)
                NSColor.systemRed.setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                drawText(String(badge.prefix(3)), in: rect.insetBy(dx: 4, dy: 2), font: .systemFont(ofSize: 9, weight: .bold), color: .white)
            }
        }
        for (index, collection) in model.collections.enumerated() where index < collectionFrames.count {
            let rect = collectionFrames[index]
            foreground.withAlphaComponent(0.07).setFill(); NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            let images = index < collectionIcons.count ? collectionIcons[index] : []
            if images.isEmpty { drawSymbol(collection.symbol, in: rect.insetBy(dx: 9, dy: 9), color: accentColor) }
            for (i, image) in images.enumerated() {
                let side = rect.width * 0.35
                image.draw(in: NSRect(x: rect.minX + 4 + CGFloat(i % 2) * (side + 3), y: rect.maxY - side - 4 - CGFloat(i / 2) * (side + 3), width: side, height: side))
            }
        }
        for (index, link) in model.quickLinks.enumerated() where index < linkFrames.count {
            let rect = linkFrames[index]
            accentColor.withAlphaComponent(0.1).setFill(); NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            if link.kind == "web", let url = link.url, let image = SiteIconCache.shared.image(for: url) {
                image.draw(in: rect.insetBy(dx: 5, dy: 5))
            } else if link.kind == "file" { NSWorkspace.shared.icon(forFile: link.destination).draw(in: rect.insetBy(dx: 3, dy: 3)) }
            else { drawSymbol(link.symbol, in: rect.insetBy(dx: 8, dy: 8), color: accentColor) }
        }
        if model.showSeparator, widgetWidth > 0 {
            foreground.withAlphaComponent(0.13).setFill()
            let separator = model.dockEdge.isVertical
                ? NSRect(x: barRect.minX + 13, y: widgetRect.maxY + 7, width: max(1, barRect.width - 26), height: 0.6)
                : NSRect(x: widgetRect.minX - 7, y: barRect.minY + 13, width: 0.6, height: max(1, barRect.height - 26))
            NSBezierPath(rect: separator).fill()
        }
        for (kind, rect) in zip(model.widgetKinds, widgetFrames) { drawWidget(foreground, kind: kind, rect: rect) }
        if model.showSettingsButton { drawSymbol("slider.horizontal.3", in: settingsRect.insetBy(dx: 4, dy: 4), color: foreground.withAlphaComponent(0.5)) }
        if model.showLabels, let point = pointer, draggedID == nil {
            if let index = hitItem(point), index < items.count { drawLabel(items[index].name, frame: frames[index]) }
            else if let index = linkFrames.firstIndex(where: { $0.contains(point) }), index < model.quickLinks.count { drawLabel(model.quickLinks[index].name, frame: linkFrames[index]) }
            else if let index = spaceFrames.firstIndex(where: { $0.contains(point) }), index < model.spaces.count { drawLabel(model.spaces[index].name, frame: spaceFrames[index]) }
        }
        if let insertion {
            let center = insertion < frames.count ? axis(NSPoint(x: frames[insertion].midX, y: frames[insertion].midY)) - step / 2 : frames.last.map { axis(NSPoint(x: $0.midX, y: $0.midY)) + step / 2 } ?? spacesWidth
            let length = model.dockEdge.isVertical ? bounds.height : bounds.width
            let rect = orient(NSRect(x: min(length - 4, max(2, center)), y: 15, width: 3, height: max(10, CGFloat(model.iconSize) - 2)))
            NSColor.systemTeal.setFill(); NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
    private func drawLabel(_ name: String, frame: NSRect) {
        let width = min(CGFloat(name.count * 7 + 22), model.dockEdge.isVertical ? 180 : bounds.width - 4)
        var rect: NSRect
        switch model.dockEdge {
        case .bottom: rect = NSRect(x: frame.midX - width / 2, y: frame.maxY + 8, width: width, height: 25)
        case .top: rect = NSRect(x: frame.midX - width / 2, y: frame.minY - 33, width: width, height: 25)
        case .left: rect = NSRect(x: frame.maxX + 8, y: frame.midY - 12, width: width, height: 25)
        case .right: rect = NSRect(x: frame.minX - width - 8, y: frame.midY - 12, width: width, height: 25)
        }
        rect.origin.x = max(2, min(bounds.width - width - 2, rect.origin.x))
        rect.origin.y = max(2, min(bounds.height - 27, rect.origin.y))
        NSColor(white: 0.12, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        drawText(name, in: rect.insetBy(dx: 11, dy: 5), font: .systemFont(ofSize: 11, weight: .medium), color: .white)
    }

    var accentColor: NSColor { ["violet": NSColor.systemPurple, "cyan": .systemCyan, "mint": .systemMint, "blue": .systemBlue, "orange": .systemOrange, "rose": .systemPink, "neutral": .gray][model.widgetAccent] ?? .systemPurple }
    private func drawWidget(_ foreground: NSColor, kind: String, rect: NSRect) {
        guard widgetWidth > 0 else { return }
        accentColor.withAlphaComponent(model.widgetOpacity).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11).fill()
        let compact = compactWidgets
        var r = rect
        if compact {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.minX, yBy: rect.minY)
            transform.scaleX(by: rect.width / 44, yBy: rect.height / 44)
            transform.concat(); r = NSRect(x: 0, y: 0, width: 44, height: 44)
        }
        defer { if compact { NSGraphicsContext.restoreGraphicsState() } }
        if compact {
            if kind == "music" {
                if let image = music.artwork { NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect: r.insetBy(dx: 3, dy: 3), xRadius: 8, yRadius: 8).addClip(); image.draw(in: r.insetBy(dx: 3, dy: 3)); NSGraphicsContext.restoreGraphicsState() }
                else { drawSymbol("music.note", in: r.insetBy(dx: 10, dy: 10), color: foreground) }
            } else if kind == "calendar" {
                let f = DateFormatter(); f.locale = Localization.shared.locale; f.dateFormat = "MMM"
                drawText(f.string(from: Date()).uppercased(), in: NSRect(x: r.minX + 6, y: r.maxY - 12, width: r.width - 8, height: 9), font: .systemFont(ofSize: 6.5, weight: .bold), color: foreground.withAlphaComponent(0.6))
                f.dateFormat = "d"; drawText(f.string(from: Date()), in: NSRect(x: r.minX + 9, y: r.minY + 4, width: r.width - 12, height: 25), font: .systemFont(ofSize: 21, weight: .semibold), color: foreground)
            } else if kind == "timer" {
                let path = NSBezierPath(ovalIn: r.insetBy(dx: 5, dy: 5)); foreground.withAlphaComponent(0.2).setStroke(); path.lineWidth = 1.5; path.stroke()
                let progress = NSBezierPath(); progress.appendArc(withCenter: NSPoint(x: r.midX, y: r.midY), radius: max(4, r.height / 2 - 5), startAngle: 90, endAngle: 90 - CGFloat(focus.progress) * 360, clockwise: true); foreground.setStroke(); progress.lineWidth = 2; progress.stroke()
                drawText(focus.text, in: NSRect(x: r.minX + 5, y: r.midY - 5, width: r.width - 6, height: 11), font: .monospacedDigitSystemFont(ofSize: 8, weight: .semibold), color: foreground)
            } else {
                let f = DateFormatter(); f.dateFormat = model.clockFormat == "12h" ? "h" : "HH"
                drawText(f.string(from: Date()), in: NSRect(x: r.minX + 10, y: r.midY - 1, width: r.width - 10, height: 19), font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold), color: foreground)
                f.dateFormat = "mm"; drawText(f.string(from: Date()), in: NSRect(x: r.minX + 10, y: r.minY + 4, width: r.width - 10, height: 17), font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium), color: foreground.withAlphaComponent(0.65))
            }
            return
        }
        if kind == "calendar" {
            let f = DateFormatter(); f.locale = Localization.shared.locale; f.dateFormat = "d"
            drawText(f.string(from: Date()), in: NSRect(x: r.minX + 10, y: r.minY + 4, width: 30, height: 28), font: .systemFont(ofSize: 25, weight: .semibold), color: foreground)
            let next = agenda.nextEvent
            drawText(next?.title ?? L("Твой календарь"), in: NSRect(x: r.minX + 46, y: r.midY, width: r.width - 52, height: 15), font: .systemFont(ofSize: 9, weight: .semibold), color: foreground)
            f.dateFormat = "EEE, d MMM"
            drawText(next.map { $0.time + " · " + $0.calendar } ?? f.string(from: Date()), in: NSRect(x: r.minX + 46, y: r.minY + 6, width: r.width - 52, height: 12), font: .systemFont(ofSize: 7.5), color: foreground.withAlphaComponent(0.6))
        } else if kind == "clock" {
            let time = DateFormatter(); time.dateFormat = (model.clockFormat == "12h" ? "h:mm" : "HH:mm") + (model.clockSeconds ? ":ss" : "") + (model.clockFormat == "12h" ? " a" : "")
            let date = DateFormatter(); date.locale = Localization.shared.locale; date.setLocalizedDateFormatFromTemplate("EEEEdMMM")
            drawText(time.string(from: Date()), in: NSRect(x: r.minX + 13, y: r.midY - 1, width: r.width - 22, height: 21), font: .monospacedDigitSystemFont(ofSize: model.clockSeconds ? 16 : 18, weight: .semibold), color: foreground)
            drawText(date.string(from: Date()).capitalized, in: NSRect(x: r.minX + 13, y: r.minY + 5, width: r.width - 18, height: 12), font: .systemFont(ofSize: 8.5, weight: .medium), color: foreground.withAlphaComponent(0.6))
        } else if kind == "timer" {
            drawSymbol(focus.isRunning ? "pause.circle.fill" : "play.circle.fill", in: NSRect(x: r.minX + 11, y: r.midY - 11, width: 22, height: 22), color: foreground)
            drawText(focus.text, in: NSRect(x: r.minX + 43, y: r.midY - 1, width: r.width - 48, height: 20), font: .monospacedDigitSystemFont(ofSize: 18, weight: .semibold), color: foreground)
            drawText(focus.isRunning ? L("Время для фокуса") : L("Нажми, чтобы начать"), in: NSRect(x: r.minX + 43, y: r.minY + 5, width: r.width - 48, height: 12), font: .systemFont(ofSize: 8), color: foreground.withAlphaComponent(0.6))
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
    private func hitItem(_ point: NSPoint) -> Int? { BarGeometry.nearest(point, frames: frames) }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return containsInteractivePoint(local) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        barRect.contains(point) || frames.contains { $0.contains(point) }
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil); downIndex = downPoint.flatMap(hitItem)
    }
    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil; downIndex = nil }
        let point = convert(event.locationInWindow, from: nil)
        if let index = downIndex, index == hitItem(point), index < model.items.count { activate(model.items[index]); return }
        if model.showSettingsButton && settingsRect.insetBy(dx: -5, dy: -10).contains(point) { openSettings?(); return }
        if let index = spaceFrames.firstIndex(where: { $0.contains(point) }), index < model.spaces.count { model.selectSpace(model.spaces[index].id); return }
        if model.showTrash && trashRect.contains(point) { NSWorkspace.shared.open(BarModel.trashURL); return }
        if let index = collectionFrames.firstIndex(where: { $0.contains(point) }), index < model.collections.count { openCollection?(model.collections[index], collectionFrames[index]); return }
        if let index = linkFrames.firstIndex(where: { $0.contains(point) }), index < model.quickLinks.count {
            let link = model.quickLinks[index]
            if let url = link.url { if link.kind == "folder" { openFolder?(url, linkFrames[index]) } else { ActionRouter.open(.resource(url)) } }; return
        }
        for (kind, rect) in zip(model.widgetKinds, widgetFrames) where rect.contains(point) {
            if kind == "music", !compactWidgets, point.y <= rect.minY + 18, point.x >= rect.maxX - 70 {
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
        let pasteboard = NSPasteboardItem(); pasteboard.setString(item.id, forType: NSPasteboard.PasteboardType("app.panopticon.item"))
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
        let internalDrag = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("app.panopticon.item")) != nil
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL] ?? []
        if (model.showTrash && trashRect.contains(point)) || spaceFrames.contains(where: { $0.contains(point) }) { insertion = nil; dropTarget = nil; return internalDrag ? .move : .copy }
        if !internalDrag && urls.contains(where: { $0.pathExtension.lowercased() != "app" }), let index = hitItem(point) {
            dropTarget = index; insertion = nil; needsDisplay = true; return .copy
        }
        dropTarget = nil
        insertion = min(frames.firstIndex(where: { axis(point) < axis(NSPoint(x: $0.midX, y: $0.midY)) }) ?? frames.count, model.pinned.count)
        needsDisplay = true
        return internalDrag ? .move : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { insertion = nil; dropTarget = nil; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        let boundary = insertion ?? model.pinned.count
        defer { insertion = nil; dropTarget = nil; needsDisplay = true }
        if let id = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType("app.panopticon.item")), let item = model.pinned.first(where: { $0.id == id }) {
            if model.showTrash && trashRect.contains(point) { model.remove(item) }
            else if let index = spaceFrames.firstIndex(where: { $0.contains(point) }), index < model.spaces.count { model.moveApp(item, toSpace: model.spaces[index].id) }
            else { model.move(id, to: boundary) }; return true
        }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL] else { return false }
        if model.showTrash && trashRect.contains(point) {
            guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return false }
            NSWorkspace.shared.recycle(urls) { _, error in if let error { DispatchQueue.main.async { ActionRouter.showError(error.localizedDescription) } } }; return true
        }
        if let index = spaceFrames.firstIndex(where: { $0.contains(point) }), index < model.spaces.count {
            model.selectSpace(model.spaces[index].id); model.addFiles(urls); return true
        }
        if let index = dropTarget, index < model.items.count {
            NSWorkspace.shared.open(urls, withApplicationAt: model.items[index].url, configuration: .init()) { _, error in
                if let error { DispatchQueue.main.async { ActionRouter.showError(error.localizedDescription) } }
            }
            return true
        }
        var accepted = false
        for (offset, url) in urls.enumerated() {
            if !url.isFileURL { accepted = model.addQuickLink(name: url.host ?? L("Сайт"), kind: "web", destination: url.absoluteString) || accepted; continue }
            if url.pathExtension.lowercased() == "app" {
                let before = model.pinned.count; model.add(url, at: boundary + offset)
                accepted = model.pinned.count != before || accepted
            }
            else {
                let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                accepted = model.addQuickLink(name: FileManager.default.displayName(atPath: url.path), kind: directory ? "folder" : "file", destination: url.path) || accepted
            }
        }
        return accepted
    }
    override func scrollWheel(with event: NSEvent) {
        guard model.scrollToSwitch, event.momentumPhase.isEmpty else { return }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? -event.scrollingDeltaX : event.scrollingDeltaY
        scrollAccumulator += event.hasPreciseScrollingDeltas ? delta : delta * 12
        if abs(scrollAccumulator) > 40, Date().timeIntervalSince(lastScrollSwitch) > 0.3 {
            model.cycleSpace(scrollAccumulator > 0 ? -1 : 1); scrollAccumulator = 0; lastScrollSwitch = Date()
        }
        if event.phase == .ended || event.phase == .cancelled { scrollAccumulator = 0 }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let point = convert(event.locationInWindow, from: nil)
        if let index = spaceFrames.firstIndex(where: { $0.contains(point) }), index < model.spaces.count { return spaceMenu(model.spaces[index]) }
        if model.showTrash && trashRect.contains(point) {
            menu.addItem(ActionMenuItem(L("Открыть Корзину")) { NSWorkspace.shared.open(BarModel.trashURL) })
            menu.addItem(ActionMenuItem(L("Очистить Корзину…")) { DispatchQueue.main.async { TrashActions.confirmEmpty() } }); return menu
        }
        if let index = hitItem(point), index < model.items.count {
            let item = model.items[index]
            if let app = model.running.first(where: { $0.bundleIdentifier == item.bundleID }) {
                for window in AX.windows(of: app) { menu.addItem(ActionMenuItem(window.title) { AX.focus(window, of: app) }) }
                if !menu.items.isEmpty { menu.addItem(.separator()) }
            }
            if model.pinned.contains(item) {
                let spaces = NSMenu()
                for space in model.spaces where space.id != model.selectedSpaceID {
                    spaces.addItem(ActionMenuItem(space.name) { [weak self] in self?.model.moveApp(item, toSpace: space.id) })
                }
                let entry = NSMenuItem(title: L("Переместить в пространство"), action: nil, keyEquivalent: ""); entry.submenu = spaces; menu.addItem(entry)
            }
            addMenu(menu, item.name, #selector(openItem(_:)), item)
            addMenu(menu, model.pinned.contains(item) ? L("Убрать из закреплённых") : L("Закрепить в панели"), #selector(pinItem(_:)), item)
            addMenu(menu, L("Показать в Finder"), #selector(revealItem(_:)), item)
            if model.isRunning(item), item.bundleID != "com.apple.finder" {
                addMenu(menu, L("Скрыть / показать приложение"), #selector(hideItem(_:)), item)
                addMenu(menu, L("Завершить приложение"), #selector(quitItem(_:)), item)
                let force = NSMenuItem(title: L("Завершить принудительно"), action: #selector(forceQuitItem(_:)), keyEquivalent: "")
                force.target = self; force.representedObject = item; force.isAlternate = true; force.keyEquivalentModifierMask = .option
                menu.addItem(force)
            }
            menu.addItem(.separator())
        }
        if zip(model.widgetKinds, widgetFrames).contains(where: { $0.0 == "timer" && $0.1.contains(point) }) { addMenu(menu, L("Сбросить таймер"), #selector(resetTimer(_:)), nil); menu.addItem(.separator()) }
        addMenu(menu, L("Открыть выбранный календарь"), #selector(calendarAction(_:)), nil)
        addMenu(menu, L("Настройки Panopticon…"), #selector(settingsAction(_:)), nil)
        addMenu(menu, L("Завершить Panopticon"), #selector(quitBar(_:)), nil)
        return menu
    }
    private func spaceMenu(_ space: BarSpace) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(L("Открыть «\(space.name)»")) { [weak self] in self?.model.selectSpace(space.id) })
        menu.addItem(ActionMenuItem(L("Привязать к текущему рабочему столу"), enabled: model.currentDesktop != nil) { [weak self] in
            guard let self else { return }; self.model.bindSpace(space.id, desktop: self.model.currentDesktop)
        })
        menu.addItem(ActionMenuItem(L("Снять привязку"), enabled: space.desktop != nil) { [weak self] in self?.model.bindSpace(space.id, desktop: nil) })
        addMenu(menu, L("Настроить пространства…"), #selector(settingsAction(_:)), nil)
        return menu
    }
    private func addMenu(_ menu: NSMenu, _ title: String, _ action: Selector, _ item: DockItem?) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; entry.representedObject = item; menu.addItem(entry)
    }
    @objc private func openItem(_ sender: NSMenuItem) { if let item = sender.representedObject as? DockItem { model.launch(item) } }
    @objc private func pinItem(_ sender: NSMenuItem) { if let item = sender.representedObject as? DockItem { model.pinned.contains(item) ? model.remove(item) : model.add(item.url) } }
    @objc private func revealItem(_ sender: NSMenuItem) { if let item = sender.representedObject as? DockItem { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } }
    @objc private func quitItem(_ sender: NSMenuItem) { if let item = sender.representedObject as? DockItem { model.running.first { $0.bundleIdentifier == item.bundleID }?.terminate() } }
    @objc private func hideItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DockItem, let app = model.running.first(where: { $0.bundleIdentifier == item.bundleID }) else { return }
        if app.isHidden { app.unhide() } else { app.hide() }
    }
    @objc private func forceQuitItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? DockItem { model.running.first { $0.bundleIdentifier == item.bundleID }?.forceTerminate() }
    }
    @objc private func calendarAction(_ sender: Any?) { model.openCalendar() }
    @objc private func resetTimer(_ sender: Any?) { focus.reset(minutes: model.timerMinutes) }
    @objc private func settingsAction(_ sender: Any?) { openSettings?() }
    @objc private func quitBar(_ sender: Any?) { NSApp.terminate(nil) }
}
