import AppKit

final class BarAccessibilityButton: NSAccessibilityElement {
    var frameProvider: (() -> NSRect)?
    override func accessibilityFrame() -> NSRect { frameProvider?() ?? super.accessibilityFrame() }
    var valueProvider: (() -> String?)?
    override func accessibilityValue() -> Any? { valueProvider?() ?? super.accessibilityValue() }
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        guard let press else { return false }
        press()
        return true
    }
}

final class BarView: NSView, NSDraggingSource {
    let model: BarModel
    let music: MusicController
    let focus: FocusTimer
    let agenda: CalendarController
    var openFolder: ((URL, NSRect) -> Void)?
    var openFocus: ((NSRect) -> Void)?
    var openAgenda: ((NSRect) -> Void)?
    var openCollection: ((AppCollection, NSRect) -> Void)?
    var openSettings: (() -> Void)?
    var openMusic: ((NSRect) -> Void)?
    var availableLength: CGFloat = 1400 { didSet { if availableLength != oldValue { cachedLayout = nil } } }
    let glass = NSVisualEffectView()
    let surfaceShadow = NSView()
    let innerRim = CAShapeLayer()
    var overflowRect: NSRect = .zero
    var downLink: Int?
    var downCollection: Int?
    var dropFeedback: NSRect?
    var undoRemoval: (() -> Void)?
    var tracking: NSTrackingArea?
    let surfaceTint = CAGradientLayer()
    var spaceFrames: [NSRect] = []
    var trashRect: NSRect = .zero
    var scrollAccumulator: CGFloat = 0
    var lastScrollSwitch = Date.distantPast
    var pointer: NSPoint?
    var frames: [NSRect] = []
    var sizes: [CGFloat] = []
    var springs: [DockSpring] = []
    var appearing: [String: TimeInterval] = [:]
    var lastAnimationTime: TimeInterval?
    var animation: Timer?
    var downPoint: NSPoint?
    var downIndex: Int?
    var dropTarget: Int?
    var insertion: Int?
    var draggedID: String?
    var hasActiveDrag: Bool { draggedID != nil }
    var cachedCollections: [AppCollection] = []
    var collectionIcons: [[NSImage]] = []
    var lastItems: [String] = []
    var lastBase: CGFloat = 0
    var icons: [String: NSImage] = [:]
    private(set) var barRect: NSRect = .zero
    var widgetRect: NSRect = .zero
    var widgetFrames: [NSRect] = []
    var linkFrames: [NSRect] = []
    var collectionFrames: [NSRect] = []
    var launchTime: Date?
    var launchID: String?
    var settingsRect: NSRect = .zero
    var step: CGFloat { CGFloat(model.iconSize + model.iconSpacing) }
    var cachedLayout: PanelContentLayout?
    var systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    var contentLayout: PanelContentLayout {
        if let cachedLayout { return cachedLayout }
        let result = PanelContentLayout(model: model, availableLength: availableLength, reduceMotion: motionReduced)
        cachedLayout = result; return result
    }
    func preparePresentation() {
        systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        cachedLayout = PanelContentLayout(model: model, availableLength: availableLength, reduceMotion: motionReduced)
    }
    var compactWidgets: Bool { contentLayout.compact }
    var visibleSpaces: [BarSpace] {
        guard model.showSpaces else { return [] }
        return contentLayout.collapsedSpaces ? model.spaces.filter { $0.id == model.selectedSpaceID } : model.spaces
    }
    var visibleWidgets: [String] { Array(model.widgetKinds.prefix(contentLayout.widgets)) }
    var displayItems: [DockItem] { Array(model.items.prefix(contentLayout.apps)) }
    var displayCollections: [AppCollection] { Array(model.collections.prefix(contentLayout.collections)) }
    var displayLinks: [QuickLink] { Array(model.quickLinks.prefix(contentLayout.links)) }
    var hasOverflow: Bool { contentLayout.overflow }
    var widgetWidth: CGFloat { contentLayout.widgetWidth }
    var widgetTotalWidth: CGFloat { contentLayout.widgetTotalWidth }
    var motionReduced: Bool {
        (DockMotionMode(rawValue: model.motionMode) ?? .system).isReduced(
            system: systemReduceMotion, legacy: model.reduceMotion)
    }
    var spacesWidth: CGFloat { contentLayout.spacesWidth }
    var trashWidth: CGFloat { contentLayout.trashWidth }
    var baseWidth: CGFloat { contentLayout.baseWidth }
    var preferredLength: CGFloat { min(availableLength, baseWidth + contentLayout.hoverAllowance + 8) }
    var preferredThickness: CGFloat {
        CGFloat(model.iconSize) * CGFloat(model.magnification) + CGFloat(model.hoverLift) + 48
            + (model.dockEdge.isVertical && model.showLabels ? 180 : 0)
    }

    var preferredWidth: CGFloat { preparePresentation(); return model.dockEdge.isVertical ? preferredThickness : preferredLength }
    var preferredHeight: CGFloat { preparePresentation(); return model.dockEdge.isVertical ? preferredLength : preferredThickness }

    init(model: BarModel, music: MusicController, focus: FocusTimer, agenda: CalendarController) {
        self.model = model
        self.music = music
        self.focus = focus
        self.agenda = agenda
        super.init(frame: .zero)
        wantsLayer = true
        SiteIconCache.shared.onChange = { [weak self] in self?.needsDisplay = true }
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.material = .hudWindow
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 24
        glass.layer?.masksToBounds = true
        surfaceTint.startPoint = CGPoint(x: 0, y: 0)
        surfaceTint.endPoint = CGPoint(x: 1, y: 1)
        glass.layer?.addSublayer(surfaceTint)
        innerRim.fillColor = NSColor.clear.cgColor
        innerRim.lineWidth = 1
        glass.layer?.addSublayer(innerRim)
        surfaceShadow.wantsLayer = true
        surfaceShadow.layer?.shadowColor = NSColor.black.cgColor
        surfaceShadow.layer?.shadowOpacity = 0.22
        surfaceShadow.layer?.shadowRadius = 12
        surfaceShadow.layer?.shadowOffset = CGSize(width: 0, height: -3)
        registerForDraggedTypes([
            .fileURL, .URL, PanelActions.item, PanelActions.link, PanelActions.collection,
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("Panopticon — панель приложений"))

    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { animation?.invalidate() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        updatePointer(convert(event.locationInWindow, from: nil))
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        updatePointer(nil)
    }
    /// Global mouse tracking also reaches the nonactivating panel while its
    /// transparent margin is passing events to another application.
    func updatePointer(_ point: NSPoint?) {
        let next = point.flatMap { hoverRegion.contains($0) ? $0 : nil }
        guard next != pointer else { return }
        pointer = next
        startAnimation()
        needsDisplay = true
    }
    var hoverRegion: NSRect {
        frames.reduce(barRect) { $0.union($1) }.insetBy(dx: -12, dy: -20)
    }
    func refresh() {
        setAccessibilityLabel(L("Panopticon — панель приложений"))
        preparePresentation()
        glass.appearance = model.dockTheme.appearance ?? NSApp.effectiveAppearance
        appearance = model.dockTheme.appearance ?? NSApp.effectiveAppearance
        let ids = displayItems.map(\.id)
        if ids != lastItems || lastBase != CGFloat(model.iconSize) {
            let old = Dictionary(uniqueKeysWithValues: zip(lastItems, springs))
            springs = ids.map { lastBase == CGFloat(model.iconSize) ? old[$0] ?? DockSpring(value: CGFloat(model.iconSize)) : DockSpring(value: CGFloat(model.iconSize)) }
            sizes = springs.map(\.value)
            if !motionReduced {
                let now = ProcessInfo.processInfo.systemUptime
                let previous = Set(lastItems)
                for (index, id) in ids.filter({ !previous.contains($0) }).enumerated() {
                    appearing[id] = now + Double(min(index, 6)) * 0.018
                }
            }
            appearing = appearing.filter { ids.contains($0.key) }
        }
        lastItems = ids
        lastBase = CGFloat(model.iconSize)
        let groups = displayCollections
        if groups != cachedCollections {
            cachedCollections = groups
            collectionIcons = groups.map { $0.items.prefix(4).map(\.icon) }
        }
        let neededIcons = Set(
            displayItems.map(\.id) + displayLinks.filter { $0.kind == "file" }.map(\.destination))
        icons = icons.filter { neededIcons.contains($0.key) }
        layoutIcons()
        updateAccessibility()
        needsDisplay = true
        if !appearing.isEmpty || pointer != nil { startAnimation() }
    }
    func updateAccessibility() {
        var elements: [BarAccessibilityButton] = []
        for (index, item) in displayItems.enumerated() where index < frames.count {
            let element = BarAccessibilityButton()
            element.setAccessibilityRole(.button)
            element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(item.name + (model.isRunning(item) ? L(" — запущено") : ""))
            element.setAccessibilityParent(self)
            element.valueProvider = { [weak self] in self?.model.badge(for: item).map { L("Бейдж ") + $0 } }
            element.setAccessibilityFrame(
                window?.convertToScreen(convert(frames[index], to: nil)) ?? frames[index])
            element.frameProvider = { [weak self] in
                guard let self, index < self.frames.count else { return .zero }
                return self.screenRect(self.frames[index])
            }
            element.press = { [weak self] in self?.activate(item) }
            elements.append(element)
        }
        let settings = BarAccessibilityButton()
        settings.setAccessibilityRole(.button)
        settings.setAccessibilityEnabled(true)
        settings.setAccessibilityLabel(L("Настройки Panopticon"))
        settings.setAccessibilityParent(self)
        settings.setAccessibilityFrame(
            window?.convertToScreen(convert(settingsRect, to: nil)) ?? settingsRect)
        settings.frameProvider = { [weak self] in
            guard let self else { return .zero }
            return self.screenRect(self.settingsRect)
        }
        settings.press = { [weak self] in self?.openSettings?() }
        if contentLayout.showsSettings { elements.append(settings) }
        if hasOverflow {
            let more = BarAccessibilityButton()
            more.setAccessibilityRole(.button)
            more.setAccessibilityEnabled(true)
            more.setAccessibilityLabel(L("Все элементы и пространства"))
            more.setAccessibilityParent(self)
            more.frameProvider = { [weak self] in
                guard let self else { return .zero }
                return self.screenRect(self.overflowRect)
            }
            more.press = { [weak self] in self?.showOverflow() }
            elements.append(more)
        }
        for (index, collection) in displayCollections.enumerated() where index < collectionFrames.count {
            let element = BarAccessibilityButton()
            element.setAccessibilityRole(.button)
            element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(L("Коллекция ") + collection.name)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrame(
                window?.convertToScreen(convert(collectionFrames[index], to: nil)) ?? collectionFrames[index])
            element.frameProvider = { [weak self] in
                guard let self, index < self.collectionFrames.count else { return .zero }
                return self.screenRect(self.collectionFrames[index])
            }
            element.press = { [weak self] in
                guard let self, index < self.collectionFrames.count else { return }
                self.openCollection?(collection, self.collectionFrames[index])
            }
            elements.append(element)
        }
        for (index, link) in displayLinks.enumerated() where index < linkFrames.count {
            let element = BarAccessibilityButton()
            element.setAccessibilityRole(.button)
            element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(link.name)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrame(
                window?.convertToScreen(convert(linkFrames[index], to: nil)) ?? linkFrames[index])
            element.frameProvider = { [weak self] in
                guard let self, index < self.linkFrames.count else { return .zero }
                return self.screenRect(self.linkFrames[index])
            }
            element.press = { [weak self] in
                guard let self, index < self.linkFrames.count, let url = link.url else { return }
                if link.kind == "folder" {
                    self.openFolder?(url, self.linkFrames[index])
                } else {
                    ActionRouter.open(.resource(url))
                }
            }
            elements.append(element)
        }
        for (kind, rect) in zip(visibleWidgets, widgetFrames) {
            let widget = BarAccessibilityButton()
            widget.setAccessibilityRole(.button)
            widget.setAccessibilityEnabled(true)
            let label =
                [
                    "music": L("Открыть музыкальный плеер"), "clock": L("Часы"), "calendar": L("Календарь и события"),
                    "timer": L("Таймер фокуса"),
                ][kind] ?? L("Виджет")
            widget.setAccessibilityLabel(label)
            widget.setAccessibilityParent(self)
            widget.valueProvider = { [weak self] in
                guard let self else { return nil }
                switch kind {
                case "music": return self.music.permissionDenied ? L("Нет доступа к плееру") : self.music.title + ", " + self.music.artist + (self.music.playing ? L(", воспроизводится") : L(", пауза"))
                case "timer": return self.focus.text + (self.focus.isRunning ? L(", таймер запущен") : L(", таймер остановлен"))
                case "calendar": return Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Localization.shared.locale)) + (self.agenda.nextEvent.map { ", " + $0.title + ", " + $0.time } ?? "")
                default:
                    let formatter = DateFormatter(); formatter.locale = Localization.shared.locale
                    formatter.dateFormat = (self.model.clockFormat == "12h" ? "h:mm" : "HH:mm") + (self.model.clockSeconds ? ":ss" : "") + (self.model.clockFormat == "12h" ? " a" : "")
                    return formatter.string(from: Date())
                }
            }
            widget.setAccessibilityFrame(window?.convertToScreen(convert(rect, to: nil)) ?? rect)
            widget.frameProvider = { [weak self] in
                guard let self, let i = self.visibleWidgets.firstIndex(of: kind), i < self.widgetFrames.count
                else { return .zero }
                return self.screenRect(self.widgetFrames[i])
            }
            widget.press = { [weak self] in
                guard let self, let i = self.visibleWidgets.firstIndex(of: kind), i < self.widgetFrames.count
                else { return }
                self.activateWidget(kind, rect: self.widgetFrames[i])
            }
            elements.append(widget)
        }
        for (index, space) in visibleSpaces.enumerated() where index < spaceFrames.count {
            let element = BarAccessibilityButton()
            element.setAccessibilityRole(.button)
            element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(
                L("Пространство ") + space.name + (space.id == model.selectedSpaceID ? L(" — выбрано") : ""))
            element.setAccessibilityParent(self)
            element.frameProvider = { [weak self] in
                guard let self, index < self.spaceFrames.count else { return .zero }
                return self.screenRect(self.spaceFrames[index])
            }
            element.press = { [weak self] in self?.model.selectSpace(space.id) }
            elements.append(element)
        }
        if contentLayout.showsTrash {
            let trash = BarAccessibilityButton()
            trash.setAccessibilityRole(.button)
            trash.setAccessibilityEnabled(true)
            trash.setAccessibilityLabel(L("Корзина"))
            trash.setAccessibilityParent(self)
            trash.frameProvider = { [weak self] in
                guard let self else { return .zero }
                return self.screenRect(self.trashRect)
            }
            trash.press = { NSWorkspace.shared.open(BarModel.trashURL) }
            elements.append(trash)
        }
        setAccessibilityChildren(elements)
    }
    func screenRect(_ rect: NSRect) -> NSRect {
        window?.convertToScreen(convert(rect, to: nil)) ?? rect
    }
    override func layout() {
        super.layout()
        layoutIcons()
    }
    func orient(_ rect: NSRect) -> NSRect {
        switch model.dockEdge {
        case .bottom: return rect
        case .top:
            return NSRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        case .left:
            return NSRect(x: rect.minY, y: bounds.height - rect.maxX, width: rect.height, height: rect.width)
        case .right:
            return NSRect(
                x: bounds.width - rect.maxY, y: bounds.height - rect.maxX, width: rect.height,
                height: rect.width)
        }
    }
    func axis(_ point: NSPoint) -> CGFloat {
        model.dockEdge.isVertical ? bounds.height - point.y : point.x
    }
    func layoutIcons() {
        let base = CGFloat(model.iconSize)
        let items = displayItems
        if sizes.count != items.count { sizes = Array(repeating: base, count: items.count) }
        let extra = sizes.reduce(0) { $0 + max(0, $1 - base) }
        let naturalWidth = baseWidth + extra
        let length = model.dockEdge.isVertical ? bounds.height : bounds.width
        let fit = max(0.5, min(1, (length - 8) / max(naturalWidth, 1)))
        let barWidth = naturalWidth * fit
        let canonical = NSRect(x: (length - barWidth) / 2, y: 5, width: barWidth, height: (base + 18) * fit)
        barRect = orient(canonical)
        glass.frame = barRect
        let radius = min(CGFloat(model.cornerRadius), min(barRect.width, barRect.height) / 2)
        glass.layer?.cornerRadius = radius
        glass.layer?.borderWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 2 : 1
        glass.layer?.borderColor =
            model.dockTheme.palette.border.cgColor
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        glass.state = opaque ? .inactive : .active
        glass.material = model.dockTheme.isLight ? .menu : .hudWindow
        glass.layer?.backgroundColor =
            (opaque ? model.dockTheme.palette.solid : (model.dockTheme.isLight ? NSColor.white : NSColor.black).withAlphaComponent(model.opacity)).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceShadow.frame = barRect
        surfaceShadow.layer?.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: barRect.size), cornerWidth: radius, cornerHeight: radius, transform: nil)
        innerRim.frame = CGRect(origin: .zero, size: barRect.size)
        innerRim.path = CGPath(roundedRect: innerRim.bounds.insetBy(dx: 1, dy: 1), cornerWidth: max(0, radius - 1), cornerHeight: max(0, radius - 1), transform: nil)
        innerRim.strokeColor = model.dockTheme.palette.innerRim.cgColor
        surfaceTint.frame = CGRect(origin: .zero, size: barRect.size)
        surfaceTint.colors = model.dockTheme.nsTint.map {
            $0.withAlphaComponent(max($0.alphaComponent, model.opacity)).cgColor
        }
        surfaceTint.isHidden = model.dockTheme.nsTint.isEmpty
        CATransaction.commit()
        spaceFrames =
            model.showSpaces
            ? visibleSpaces.indices.map { i in
                orient(
                    NSRect(
                        x: canonical.minX + (10 + CGFloat(i) * 29) * fit, y: canonical.midY - 12 * fit,
                        width: 24 * fit, height: 24 * fit))
            } : []
        frames = BarGeometry.frames(
            sizes: sizes, spacing: CGFloat(model.iconSpacing),
            origin: NSPoint(x: canonical.minX + (12 + spacesWidth) * fit, y: canonical.minY + 10 * fit),
            scale: fit, base: base, lift: model.hoverStyle == "lift" ? CGFloat(model.hoverLift) : 0
        ).map(orient)
        let appEnd = sizes.reduce(CGFloat(12) + spacesWidth) { $0 + $1 + CGFloat(model.iconSpacing) }
        collectionFrames = displayCollections.indices.map { i in
            orient(
                NSRect(
                    x: canonical.minX + (appEnd + CGFloat(i) * step) * fit, y: canonical.minY + 10 * fit,
                    width: base * fit, height: base * fit))
        }
        linkFrames = displayLinks.indices.map { i in
            orient(
                NSRect(
                    x: canonical.minX + (appEnd + CGFloat(displayCollections.count + i) * step) * fit,
                    y: canonical.minY + 10 * fit, width: base * fit, height: base * fit))
        }
        let afterLinks = appEnd + CGFloat(displayCollections.count + displayLinks.count) * step
        trashRect =
            contentLayout.showsTrash
            ? orient(
                NSRect(
                    x: canonical.minX + (afterLinks + (hasOverflow ? step : 0) + 4) * fit,
                    y: canonical.minY + 10 * fit, width: base * fit, height: base * fit)) : .zero
        overflowRect =
            hasOverflow
            ? orient(
                NSRect(
                    x: canonical.minX + afterLinks * fit, y: canonical.minY + 10 * fit, width: base * fit,
                    height: base * fit)) : .zero
        let afterOverflow = afterLinks + (hasOverflow ? step : 0)
        let widgetX = canonical.minX + (afterOverflow + trashWidth + 4) * fit
        widgetFrames = visibleWidgets.indices.map { i in
            orient(
                NSRect(
                    x: widgetX + CGFloat(i) * (widgetWidth + 8) * fit, y: canonical.minY + 7 * fit,
                    width: widgetWidth * fit, height: (base + 4) * fit))
        }
        widgetRect = widgetFrames.first ?? .zero
        settingsRect = orient(
            NSRect(
                x: canonical.maxX - 34 * fit, y: canonical.midY - 12 * fit, width: 24 * fit, height: 24 * fit)
        )
    }
    func startAnimation() {
        guard animation == nil else { return }
        lastAnimationTime = ProcessInfo.processInfo.systemUptime
        let fps = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : min(120, max(60, window?.screen?.maximumFramesPerSecond ?? 60))
        let timer = Timer(timeInterval: 1 / Double(fps), repeats: true) { [weak self] _ in self?.animate() }
        timer.tolerance = 0.001
        animation = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func finishAnimations() {
        animation?.invalidate()
        animation = nil
        lastAnimationTime = nil
        pointer = nil
        launchID = nil
        launchTime = nil
        appearing.removeAll()
        springs = displayItems.map { _ in DockSpring(value: CGFloat(model.iconSize)) }
        sizes = springs.map(\.value)
        layoutIcons()
        needsDisplay = true
    }
    func animate(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard window?.isVisible == true else {
            animation?.invalidate()
            animation = nil
            lastAnimationTime = nil
            return
        }
        let base = CGFloat(model.iconSize)
        let elapsed = max(0, uptime - (lastAnimationTime ?? uptime - 1 / 60))
        lastAnimationTime = uptime
        var moving = false
        let length = model.dockEdge.isVertical ? bounds.height : bounds.width
        let origin = (length - baseWidth) / 2 + 12 + spacesWidth + base / 2
        for i in sizes.indices where i < springs.count {
            let distance = pointer.map { abs(axis($0) - (origin + CGFloat(i) * step)) } ?? .greatestFiniteMagnitude
            let target = draggedID == nil && model.hoverStyle != "none" && !motionReduced
                ? DockMotion.magnifiedSize(base: base, magnification: CGFloat(model.magnification), distance: distance, step: step) : base
            if motionReduced {
                springs[i] = DockSpring(value: target)
            } else {
                if springs[i].advance(to: target, elapsed: elapsed) { moving = true }
            }
            sizes[i] = max(base, springs[i].value)
        }
        if let launchTime {
            if Date().timeIntervalSince(launchTime) > DockMotion.launchDuration {
                self.launchTime = nil
                launchID = nil
            } else {
                moving = true
            }
        }
        appearing = motionReduced ? [:] : appearing.filter { uptime - $0.value < DockMotion.entryDuration }
        moving = moving || !appearing.isEmpty
        layoutIcons()
        needsDisplay = true
        if !moving {
            animation?.invalidate()
            animation = nil
            lastAnimationTime = nil
        }
    }
    override func draw(_ dirtyRect: NSRect) { super.draw(dirtyRect); renderPanel() }
    func activate(_ item: DockItem) {
        if model.launchStyle != "none" {
            launchTime = Date()
            launchID = item.id
            startAnimation()
        }
        model.launch(item)
    }
    func activateWidget(_ kind: String, rect: NSRect) {
        switch kind {
        case "music": openMusic?(rect)
        case "calendar": openAgenda?(rect)
        case "timer": openFocus?(rect)
        default: if model.clockAction == "agenda" { openAgenda?(rect) } else { model.openCalendar() }
        }
    }
    func hitItem(_ point: NSPoint) -> Int? { BarGeometry.nearest(point, frames: frames) }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return containsInteractivePoint(local) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        barRect.contains(point) || frames.contains { $0.contains(point) }
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        downIndex = downPoint.flatMap(hitItem)
        downLink = downPoint.flatMap { point in linkFrames.firstIndex { $0.contains(point) } }
        downCollection = downPoint.flatMap { point in collectionFrames.firstIndex { $0.contains(point) } }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer {
            downPoint = nil
            downIndex = nil
            downLink = nil
            downCollection = nil
            needsDisplay = true
        }
        let point = convert(event.locationInWindow, from: nil)
        if let index = downIndex, index == hitItem(point), index < displayItems.count {
            activate(displayItems[index])
            return
        }
        if hasOverflow && overflowRect.contains(point) {
            showOverflow()
            return
        }
        if contentLayout.showsSettings && settingsRect.insetBy(dx: -5, dy: -10).contains(point) {
            openSettings?()
            return
        }
        if let index = spaceFrames.firstIndex(where: { $0.contains(point) }), index < visibleSpaces.count {
            model.selectSpace(visibleSpaces[index].id)
            return
        }
        if contentLayout.showsTrash && trashRect.contains(point) {
            NSWorkspace.shared.open(BarModel.trashURL)
            return
        }
        if let index = collectionFrames.firstIndex(where: { $0.contains(point) }),
            index < displayCollections.count
        {
            openCollection?(displayCollections[index], collectionFrames[index])
            return
        }
        if let index = linkFrames.firstIndex(where: { $0.contains(point) }), index < displayLinks.count {
            let link = displayLinks[index]
            if let url = link.url {
                if link.kind == "folder" {
                    openFolder?(url, linkFrames[index])
                } else {
                    ActionRouter.open(.resource(url))
                }
            }
            return
        }
        for (kind, rect) in zip(visibleWidgets, widgetFrames) where rect.contains(point) {
            if kind == "music", !compactWidgets, point.y <= rect.minY + 18, point.x >= rect.maxX - 70 {
                let x = point.x - (rect.maxX - 64)
                music.command(x < 17 ? "previous track" : (x > 37 ? "next track" : "playpause"))
            } else {
                activateWidget(kind, rect: rect)
            }
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint, draggedID == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - downPoint.x, point.y - downPoint.y) > 5 else { return }
        let pasteboard = NSPasteboardItem()
        var rect = NSRect.zero
        var image: NSImage?
        if let index = downIndex, index < displayItems.count, model.pinned.contains(displayItems[index]) {
            let item = displayItems[index]
            draggedID = item.id
            pasteboard.setString(item.id, forType: PanelActions.item)
            rect = frames[index]
            image = item.icon
        } else if let index = downLink, index < displayLinks.count {
            let link = displayLinks[index]
            draggedID = link.id
            pasteboard.setString(link.id, forType: PanelActions.link)
            rect = linkFrames[index]
            image = NSImage(systemSymbolName: link.symbol, accessibilityDescription: link.name)
        } else if let index = downCollection, index < displayCollections.count {
            let group = displayCollections[index]
            draggedID = group.id
            pasteboard.setString(group.id, forType: PanelActions.collection)
            rect = collectionFrames[index]
            image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: group.name)
        } else {
            return
        }
        let drag = NSDraggingItem(pasteboardWriter: pasteboard)
        drag.setDraggingFrame(rect, contents: image)
        pointer = nil
        beginDraggingSession(with: [drag], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    { .move }
    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) { clearDrag() }
    func clearDrag() {
        draggedID = nil
        insertion = nil
        dropTarget = nil
        dropFeedback = nil
        downIndex = nil
        downPoint = nil
        downLink = nil
        downCollection = nil
        needsDisplay = true
        startAnimation()
    }
    override func cancelOperation(_ sender: Any?) { clearDrag() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        dropFeedback = nil
        insertion = nil
        dropTarget = nil
        defer { needsDisplay = true }
        guard containsInteractivePoint(point) else { return [] }
        let board = sender.draggingPasteboard
        let internalDrag = board.string(forType: PanelActions.item).map { id in model.pinned.contains { $0.id == id } } == true
            || board.string(forType: PanelActions.link).map { id in model.quickLinks.contains { $0.id == id } } == true
            || board.string(forType: PanelActions.collection).map { id in model.collections.contains { $0.id == id } } == true
        let urls = board.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL] ?? []
        guard internalDrag || (!urls.isEmpty && urls.allSatisfy(validDropURL)) else { return [] }
        if contentLayout.showsTrash && trashRect.contains(point) {
            guard internalDrag || urls.allSatisfy(\.isFileURL) else { return [] }
            dropFeedback = trashRect
            return internalDrag ? .move : .copy
        }
        if let frame = spaceFrames.first(where: { $0.contains(point) }) {
            dropFeedback = frame
            return internalDrag ? .move : .copy
        }
        if !internalDrag && urls.allSatisfy(\.isFileURL),
            urls.contains(where: { $0.pathExtension.lowercased() != "app" }), let index = hitItem(point)
        {
            dropTarget = index
            dropFeedback = frames[index]
            return .copy
        }
        if board.string(forType: PanelActions.link) != nil {
            if let frame = linkFrames.first(where: { $0.contains(point) }) { dropFeedback = frame }
        } else if board.string(forType: PanelActions.collection) != nil {
            if let frame = collectionFrames.first(where: { $0.contains(point) }) { dropFeedback = frame }
        } else {
            insertion = min(
                frames.firstIndex(where: { axis(point) < axis(NSPoint(x: $0.midX, y: $0.midY)) })
                    ?? frames.count, model.pinned.count)
        }
        return internalDrag ? .move : .copy
    }
    func validDropURL(_ url: URL) -> Bool {
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            return url.pathExtension.lowercased() != "app" || Bundle(url: url)?.bundleIdentifier != nil
        }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        insertion = nil
        dropTarget = nil
        dropFeedback = nil
        needsDisplay = true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        guard containsInteractivePoint(point) else { return false }
        let boundary = insertion ?? model.pinned.count
        defer {
            insertion = nil
            dropTarget = nil
            dropFeedback = nil
            needsDisplay = true
        }
        let board = sender.draggingPasteboard
        let targetSpace = spaceFrames.firstIndex(where: { $0.contains(point) }).map { visibleSpaces[$0].id }
        if let id = board.string(forType: PanelActions.item),
            let item = model.pinned.first(where: { $0.id == id })
        {
            if contentLayout.showsTrash && trashRect.contains(point) {
                removeAppWithUndo(item)
            } else if let targetSpace {
                guard targetSpace != model.selectedSpaceID else { return false }
                model.moveApp(item, toSpace: targetSpace)
            } else {
                model.move(id, to: boundary)
            }
            return true
        }
        if let id = board.string(forType: PanelActions.link),
            model.quickLinks.contains(where: { $0.id == id })
        {
            if contentLayout.showsTrash && trashRect.contains(point) {
                removeLinkWithUndo(id)
                return true
            }
            if let targetSpace { return PanelActions.moveLink(id, toSpace: targetSpace, model: model) }
            let boundary =
                linkFrames.firstIndex { axis(point) < axis(NSPoint(x: $0.midX, y: $0.midY)) }
                ?? model.quickLinks.count
            return PanelActions.reorderLink(id, before: boundary, model: model)
        }
        if let id = board.string(forType: PanelActions.collection),
            model.collections.contains(where: { $0.id == id })
        {
            if contentLayout.showsTrash && trashRect.contains(point) {
                removeCollectionWithUndo(id)
                return true
            }
            if let targetSpace { return PanelActions.moveCollection(id, toSpace: targetSpace, model: model) }
            let boundary =
                collectionFrames.firstIndex { axis(point) < axis(NSPoint(x: $0.midX, y: $0.midY)) }
                ?? model.collections.count
            return PanelActions.reorderCollection(id, before: boundary, model: model)
        }
        guard let urls = board.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL], !urls.isEmpty,
            urls.allSatisfy(validDropURL)
        else { return false }
        if contentLayout.showsTrash && trashRect.contains(point) {
            guard urls.allSatisfy(\.isFileURL) else { return false }
            NSWorkspace.shared.recycle(urls) { _, error in
                if let error {
                    DispatchQueue.main.async { ActionRouter.showError(error.localizedDescription) }
                }
            }
            return true
        }
        if let targetSpace {
            model.selectSpace(targetSpace)
            let before = model.currentSpace
            model.batch { model.addFiles(urls) }
            return model.currentSpace != before
        }
        if let index = dropTarget, index < displayItems.count {
            NSWorkspace.shared.open(urls, withApplicationAt: displayItems[index].url, configuration: .init())
            { _, error in
                if let error {
                    DispatchQueue.main.async { ActionRouter.showError(error.localizedDescription) }
                }
            }
            return true
        }
        var accepted = false
        model.batch {
            for (offset, url) in urls.enumerated() {
                if !url.isFileURL {
                    accepted =
                        model.addQuickLink(
                            name: url.host ?? L("Сайт"), kind: "web", destination: url.absoluteString)
                        || accepted
                    continue
                }
                if url.pathExtension.lowercased() == "app" {
                    let before = model.pinned.count
                    model.add(url, at: boundary + offset)
                    accepted = model.pinned.count != before || accepted
                } else {
                    let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    accepted =
                        model.addQuickLink(
                            name: FileManager.default.displayName(atPath: url.path),
                            kind: directory ? "folder" : "file", destination: url.path) || accepted
                }
            }
        }
        return accepted
    }
    override func scrollWheel(with event: NSEvent) {
        guard model.scrollToSwitch, event.momentumPhase.isEmpty else { return }
        let delta =
            abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? -event.scrollingDeltaX : event.scrollingDeltaY
        scrollAccumulator += event.hasPreciseScrollingDeltas ? delta : delta * 12
        if abs(scrollAccumulator) > 40, Date().timeIntervalSince(lastScrollSwitch) > 0.3 {
            model.cycleSpace(scrollAccumulator > 0 ? -1 : 1)
            scrollAccumulator = 0
            lastScrollSwitch = Date()
        }
        if event.phase == .ended || event.phase == .cancelled { scrollAccumulator = 0 }
    }
    override func menu(for event: NSEvent) -> NSMenu? { makeContextMenu(event) }
}
