import AppKit

extension BarView {
    func renderPanel() {
        let items = displayItems
        let foreground: NSColor = model.dockTheme.isLight ? .black : .white
        for (i, item) in items.enumerated() where i < frames.count {
            let image = icons[item.id] ?? item.icon
            icons[item.id] = image
            var frame = frames[i]
            var opacity: CGFloat = draggedID == item.id ? 0.4 : 1
            var lift: CGFloat = 0
            if let appeared = appearing[item.id], !motionReduced {
                let progress = DockMotion.easeOut((ProcessInfo.processInfo.systemUptime - appeared) / DockMotion.entryDuration)
                opacity *= progress
                lift -= (1 - progress) * 8
            }
            if item.id == launchID, let launchTime {
                let elapsed = Date().timeIntervalSince(launchTime)
                let t = min(max(elapsed / DockMotion.launchDuration, 0), 1)
                if motionReduced {
                    opacity *= 1 - CGFloat(sin(t * .pi)) * 0.22
                } else if model.launchStyle == "bounce" {
                    lift += DockMotion.bounce(at: elapsed)
                } else if model.launchStyle == "pulse" {
                    frame = frame.insetBy(dx: -CGFloat(sin(t * .pi) * 4), dy: -CGFloat(sin(t * .pi) * 4))
                }
            }
            switch model.dockEdge {
            case .bottom: frame.origin.y += lift
            case .top: frame.origin.y -= lift
            case .left: frame.origin.x += lift
            case .right: frame.origin.x -= lift
            }
            if downIndex == i, downPoint != nil, draggedID == nil {
                let inset = frame.width * (motionReduced ? 0.01 : 0.04)
                frame = frame.insetBy(dx: inset, dy: inset)
            }
            if dropTarget == i
                || (model.hoverGlow && pointer.map { frames[i].insetBy(dx: -4, dy: -4).contains($0) } == true)
            {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = accentColor.withAlphaComponent(0.65)
                shadow.shadowBlurRadius = 16
                shadow.shadowOffset = .zero
                shadow.set()
                accentColor.withAlphaComponent(0.09).setFill()
                NSBezierPath(roundedRect: frame.insetBy(dx: 3, dy: 3), xRadius: 10, yRadius: 10).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            image.draw(
                in: frame, from: .zero, operation: .sourceOver, fraction: opacity,
                respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            if model.isRunning(item), model.indicatorStyle != "none" {
                let active = model.activeBundleID == item.bundleID
                (active ? accentColor : foreground.withAlphaComponent(0.7)).setFill()
                let width: CGFloat = model.indicatorStyle == "dash" ? 10 : 3.5
                let indicator: NSRect
                switch model.dockEdge {
                case .bottom:
                    indicator = NSRect(
                        x: frames[i].midX - width / 2, y: barRect.minY + 3, width: width, height: 3)
                case .top:
                    indicator = NSRect(
                        x: frames[i].midX - width / 2, y: barRect.maxY - 6, width: width, height: 3)
                case .left:
                    indicator = NSRect(
                        x: barRect.minX + 3, y: frames[i].midY - width / 2, width: 3, height: width)
                case .right:
                    indicator = NSRect(
                        x: barRect.maxX - 6, y: frames[i].midY - width / 2, width: 3, height: width)
                }
                NSBezierPath(roundedRect: indicator, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
        for (index, space) in visibleSpaces.enumerated() where index < spaceFrames.count {
            let rect = spaceFrames[index]
            let selected = space.id == model.selectedSpaceID
            (selected ? accentColor.withAlphaComponent(0.75) : foreground.withAlphaComponent(0.07)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            drawSymbol(
                space.symbol, in: rect.insetBy(dx: 6, dy: 6),
                color: selected ? .white : foreground.withAlphaComponent(0.65))
        }
        if let rect = dropFeedback {
            accentColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 10, yRadius: 10).fill()
        }
        if hasOverflow {
            drawSymbol("ellipsis.circle", in: overflowRect.insetBy(dx: 4, dy: 4), color: foreground)
        }
        if contentLayout.showsTrash {
            drawSymbol(
                "trash", in: trashRect.insetBy(dx: 5, dy: 3), color: foreground.withAlphaComponent(0.7))
        }
        for (index, item) in items.enumerated() where index < frames.count {
            if let badge = model.badge(for: item), !badge.isEmpty {
                let rect = NSRect(
                    x: frames[index].maxX - 17, y: frames[index].maxY - 12, width: 22, height: 16)
                NSColor.systemRed.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                drawText(
                    String(badge.prefix(3)), in: rect.insetBy(dx: 4, dy: 2),
                    font: .systemFont(ofSize: 10, weight: .bold), color: .white)
            }
        }
        for (index, collection) in displayCollections.enumerated() where index < collectionFrames.count {
            let rect = collectionFrames[index]
            foreground.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            let images = index < collectionIcons.count ? collectionIcons[index] : []
            if images.isEmpty {
                drawSymbol(collection.symbol, in: rect.insetBy(dx: 9, dy: 9), color: accentColor)
            }
            for (i, image) in images.enumerated() {
                let side = rect.width * 0.35
                image.draw(
                    in: NSRect(
                        x: rect.minX + 4 + CGFloat(i % 2) * (side + 3),
                        y: rect.maxY - side - 4 - CGFloat(i / 2) * (side + 3), width: side, height: side))
            }
        }
        for (index, link) in displayLinks.enumerated() where index < linkFrames.count {
            let rect = linkFrames[index]
            accentColor.withAlphaComponent(0.1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            if link.kind == "web", let url = link.url, let image = SiteIconCache.shared.image(for: url) {
                image.draw(in: rect.insetBy(dx: 5, dy: 5))
            } else if link.kind == "file" {
                let image = icons[link.destination] ?? NSWorkspace.shared.icon(forFile: link.destination)
                icons[link.destination] = image
                image.draw(in: rect.insetBy(dx: 3, dy: 3))
            } else {
                drawSymbol(link.symbol, in: rect.insetBy(dx: 8, dy: 8), color: accentColor)
            }
        }
        if model.showSeparator, !visibleWidgets.isEmpty {
            foreground.withAlphaComponent(0.13).setFill()
            let separator =
                model.dockEdge.isVertical
                ? NSRect(
                    x: barRect.minX + 13, y: widgetRect.maxY + 7, width: max(1, barRect.width - 26),
                    height: 0.6)
                : NSRect(
                    x: widgetRect.minX - 7, y: barRect.minY + 13, width: 0.6,
                    height: max(1, barRect.height - 26))
            NSBezierPath(rect: separator).fill()
        }
        for (kind, rect) in zip(visibleWidgets, widgetFrames) {
            drawWidget(foreground, kind: kind, rect: rect)
        }
        if contentLayout.showsSettings {
            drawSymbol(
                "slider.horizontal.3", in: settingsRect.insetBy(dx: 4, dy: 4),
                color: foreground.withAlphaComponent(0.5))
        }
        if model.showLabels, let point = pointer, draggedID == nil {
            if let index = hitItem(point), index < items.count {
                drawLabel(items[index].name, frame: frames[index])
            } else if let index = linkFrames.firstIndex(where: { $0.contains(point) }),
                index < displayLinks.count
            {
                drawLabel(displayLinks[index].name, frame: linkFrames[index])
            } else if let index = spaceFrames.firstIndex(where: { $0.contains(point) }),
                index < visibleSpaces.count
            {
                drawLabel(visibleSpaces[index].name, frame: spaceFrames[index])
            }
        }
        if let insertion {
            let center =
                insertion < frames.count
                ? axis(NSPoint(x: frames[insertion].midX, y: frames[insertion].midY)) - step / 2
                : frames.last.map { axis(NSPoint(x: $0.midX, y: $0.midY)) + step / 2 } ?? spacesWidth
            let length = model.dockEdge.isVertical ? bounds.height : bounds.width
            let rect = orient(
                NSRect(
                    x: min(length - 4, max(2, center)), y: 15, width: 3,
                    height: max(10, CGFloat(model.iconSize) - 2)))
            NSColor.systemTeal.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
    func drawLabel(_ name: String, frame: NSRect) {
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
        drawText(
            name, in: rect.insetBy(dx: 11, dy: 5), font: .systemFont(ofSize: 11, weight: .medium),
            color: .white)
    }

    var accentColor: NSColor {
        [
            "violet": NSColor.systemPurple, "cyan": .systemCyan, "mint": .systemMint, "blue": .systemBlue,
            "orange": .systemOrange, "rose": .systemPink, "neutral": .gray,
        ][model.widgetAccent] ?? .systemPurple
    }
    func drawWidget(_ foreground: NSColor, kind: String, rect: NSRect) {
        guard widgetWidth > 0 else { return }
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let background = model.dockTheme.palette.textScrim
        background.withAlphaComponent(opaque ? 1 : max(background.alphaComponent, 0.86)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11).fill()
        accentColor.withAlphaComponent(model.widgetOpacity * 0.45).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11).fill()
        let compact = compactWidgets
        var r = rect
        if compact {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.minX, yBy: rect.minY)
            transform.scaleX(by: rect.width / 44, yBy: rect.height / 44)
            transform.concat()
            r = NSRect(x: 0, y: 0, width: 44, height: 44)
        }
        defer { if compact { NSGraphicsContext.restoreGraphicsState() } }
        if compact {
            if kind == "music" {
                if let image = music.artwork {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: r.insetBy(dx: 3, dy: 3), xRadius: 8, yRadius: 8).addClip()
                    image.draw(in: r.insetBy(dx: 3, dy: 3))
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    drawSymbol("music.note", in: r.insetBy(dx: 10, dy: 10), color: foreground)
                }
            } else if kind == "calendar" {
                let f = DateFormatter()
                f.locale = Localization.shared.locale
                f.dateFormat = "MMM"
                drawText(
                    f.string(from: Date()).uppercased(),
                    in: NSRect(x: r.minX + 6, y: r.maxY - 15, width: r.width - 8, height: 12),
                    font: .systemFont(ofSize: 10, weight: .bold), color: foreground.withAlphaComponent(0.6))
                f.dateFormat = "d"
                drawText(
                    f.string(from: Date()),
                    in: NSRect(x: r.minX + 9, y: r.minY + 4, width: r.width - 12, height: 25),
                    font: .systemFont(ofSize: 21, weight: .semibold), color: foreground)
            } else if kind == "timer" {
                let path = NSBezierPath(ovalIn: r.insetBy(dx: 5, dy: 5))
                foreground.withAlphaComponent(0.2).setStroke()
                path.lineWidth = 1.5
                path.stroke()
                let progress = NSBezierPath()
                progress.appendArc(
                    withCenter: NSPoint(x: r.midX, y: r.midY), radius: max(4, r.height / 2 - 5),
                    startAngle: 90, endAngle: 90 - CGFloat(focus.progress) * 360, clockwise: true)
                foreground.setStroke()
                progress.lineWidth = 2
                progress.stroke()
                drawText(
                    focus.text, in: NSRect(x: r.minX + 5, y: r.midY - 5, width: r.width - 6, height: 11),
                    font: .monospacedDigitSystemFont(ofSize: 8, weight: .semibold), color: foreground)
            } else {
                let f = DateFormatter()
                f.dateFormat = model.clockFormat == "12h" ? "h" : "HH"
                drawText(
                    f.string(from: Date()),
                    in: NSRect(x: r.minX + 10, y: r.midY - 1, width: r.width - 10, height: 19),
                    font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold), color: foreground)
                f.dateFormat = "mm"
                drawText(
                    f.string(from: Date()),
                    in: NSRect(x: r.minX + 10, y: r.minY + 4, width: r.width - 10, height: 17),
                    font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                    color: foreground.withAlphaComponent(0.65))
            }
            return
        }
        if kind == "calendar" {
            let f = DateFormatter()
            f.locale = Localization.shared.locale
            f.dateFormat = "d"
            drawText(
                f.string(from: Date()), in: NSRect(x: r.minX + 10, y: r.minY + 4, width: 30, height: 28),
                font: .systemFont(ofSize: 25, weight: .semibold), color: foreground)
            let next = agenda.nextEvent
            drawText(
                next?.title ?? L("Твой календарь"),
                in: NSRect(x: r.minX + 46, y: r.midY, width: r.width - 52, height: 15),
                font: .systemFont(ofSize: 10, weight: .semibold), color: foreground)
            f.dateFormat = "EEE, d MMM"
            drawText(
                next.map { $0.time + " · " + $0.calendar } ?? f.string(from: Date()),
                in: NSRect(x: r.minX + 46, y: r.minY + 6, width: r.width - 52, height: 12),
                font: .systemFont(ofSize: 7.5), color: foreground.withAlphaComponent(0.6))
        } else if kind == "clock" {
            let time = DateFormatter(); time.locale = Localization.shared.locale
            time.dateFormat =
                (model.clockFormat == "12h" ? "h:mm" : "HH:mm") + (model.clockSeconds ? ":ss" : "")
                + (model.clockFormat == "12h" ? " a" : "")
            let date = DateFormatter()
            date.locale = Localization.shared.locale
            date.setLocalizedDateFormatFromTemplate("EEEEdMMM")
            drawText(
                time.string(from: Date()),
                in: NSRect(x: r.minX + 13, y: r.midY - 1, width: r.width - 22, height: 21),
                font: .monospacedDigitSystemFont(ofSize: model.clockSeconds ? 16 : 18, weight: .semibold),
                color: foreground)
            drawText(
                date.string(from: Date()).capitalized,
                in: NSRect(x: r.minX + 13, y: r.minY + 5, width: r.width - 18, height: 12),
                font: .systemFont(ofSize: 8.5, weight: .medium), color: foreground.withAlphaComponent(0.6))
        } else if kind == "timer" {
            drawSymbol(
                focus.isRunning ? "pause.circle.fill" : "play.circle.fill",
                in: NSRect(x: r.minX + 11, y: r.midY - 11, width: 22, height: 22), color: foreground)
            drawText(
                focus.text, in: NSRect(x: r.minX + 43, y: r.midY - 1, width: r.width - 48, height: 20),
                font: .monospacedDigitSystemFont(ofSize: 18, weight: .semibold), color: foreground)
            drawText(
                focus.isRunning ? L("Время для фокуса") : L("Нажми, чтобы начать"),
                in: NSRect(x: r.minX + 43, y: r.minY + 5, width: r.width - 48, height: 12),
                font: .systemFont(ofSize: 10), color: foreground.withAlphaComponent(0.6))
        } else {
            let art = NSRect(x: r.minX + 6, y: r.minY + 6, width: r.height - 12, height: r.height - 12)
            if let image = music.artwork {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: art, xRadius: 7, yRadius: 7).addClip()
                image.draw(in: art)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                foreground.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect: art, xRadius: 7, yRadius: 7).fill()
                drawSymbol("music.note", in: art.insetBy(dx: 8, dy: 8), color: foreground)
            }
            let x = art.maxX + 8
            drawText(
                music.title, in: NSRect(x: x, y: r.maxY - 16, width: r.maxX - x - 7, height: 12),
                font: .systemFont(ofSize: 10, weight: .semibold), color: foreground)
            drawText(
                music.artist, in: NSRect(x: x, y: r.maxY - 27, width: r.maxX - x - 7, height: 11),
                font: .systemFont(ofSize: 7.5), color: foreground.withAlphaComponent(0.6))
            for (j, symbol) in ["backward.fill", music.playing ? "pause.fill" : "play.fill", "forward.fill"]
                .enumerated()
            {
                drawSymbol(
                    symbol, in: NSRect(x: r.maxX - 64 + CGFloat(j) * 21, y: r.minY + 5, width: 10, height: 9),
                    color: foreground)
            }
        }
    }
    func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
    func drawSymbol(_ name: String, in rect: NSRect, color: NSColor) {
        guard
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [color]))
        else { return }
        image.draw(in: rect)
    }
}
