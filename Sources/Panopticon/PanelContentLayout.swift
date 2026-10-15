import AppKit

/// One sizing decision reused by drawing, accessibility and input. No recursive
/// layout work during icon lookup. Hidden controls remain in the native overflow menu.
struct PanelContentLayout {
    let apps: Int
    let collections: Int
    let links: Int
    let widgets: Int
    let compact: Bool
    let collapsedSpaces: Bool
    let overflow: Bool
    let showsTrash: Bool
    let showsSettings: Bool
    let widgetWidth: CGFloat
    let widgetTotalWidth: CGFloat
    let spacesWidth: CGFloat
    let trashWidth: CGFloat
    let baseWidth: CGFloat
    let hoverAllowance: CGFloat

    init(model: BarModel, availableLength: CGFloat, reduceMotion: Bool) {
        let step = CGFloat(model.iconSize + model.iconSpacing)
        let total = model.items.count + model.collections.count + model.quickLinks.count
        let spaceCount = model.showSpaces ? model.spaces.count : 0
        let widgetCount = model.widgetKinds.count
        let hover: CGFloat = reduceMotion || model.hoverStyle == "none" ? 0 : CGFloat(model.iconSize * (model.magnification - 1) * 2.5)
        let originalCompact = model.widgetStyle == "compact" || model.dockEdge.isVertical
        let originalWidgetWidth = originalCompact ? CGFloat(model.iconSize + 4) : CGFloat(model.widgetWidth)
        let originalSpaces: CGFloat = spaceCount == 0 ? 0 : CGFloat(spaceCount) * 29 + 8
        let originalTrash: CGFloat = model.showTrash ? step + 8 : 0
        let originalSettings: CGFloat = model.showSettingsButton ? 50 : 24
        let rawWidth = originalSpaces + originalTrash + CGFloat(total) * step + CGFloat(widgetCount) * originalWidgetWidth + CGFloat(max(0, widgetCount - 1)) * 8 + (widgetCount > 0 ? 12 : 0) + originalSettings
        let constrained = rawWidth + hover + 8 > availableLength || spaceCount > 3
        let collapsed = constrained && spaceCount > 1
        let spaces: CGFloat = spaceCount == 0 ? 0 : CGFloat(collapsed ? 1 : spaceCount) * 29 + 8
        var showSettings = model.showSettingsButton
        var showTrash = model.showTrash
        if constrained && spaces + originalTrash + originalSettings + step + 8 > availableLength { showSettings = false }
        let settings: CGFloat = showSettings ? 50 : 24
        if constrained && spaces + originalTrash + settings + step + 8 > availableLength { showTrash = false }
        let trash: CGFloat = showTrash ? step + 8 : 0
        let isCompact = originalCompact || constrained
        let widgetSide: CGFloat = widgetCount == 0 ? 0 : isCompact ? CGFloat(model.iconSize + 4) : CGFloat(model.widgetWidth)
        var shownWidgets = widgetCount
        let reserve = spaces + trash + settings + (constrained ? step : 0) + (total > 0 ? step : 0) + hover + 20
        while shownWidgets > 0 && reserve + CGFloat(shownWidgets) * (widgetSide + 8) > availableLength { shownWidgets -= 1 }
        let widgetTotal = CGFloat(shownWidgets) * widgetSide + CGFloat(max(0, shownWidgets - 1)) * 8
        let fixed = spaces + trash + widgetTotal + (shownWidgets > 0 ? 12 : 0) + settings + (constrained ? step : 0) + hover + 8
        var capacity = max(0, Int((availableLength - fixed) / max(1, step)))
        var more = capacity < total || collapsed || shownWidgets < widgetCount || showSettings != model.showSettingsButton || showTrash != model.showTrash
        var width = spaces + trash + CGFloat(min(total, capacity)) * step + (more ? step : 0) + widgetTotal + (shownWidgets > 0 ? 12 : 0) + settings
        while capacity > 0 && width + (total > 0 ? hover : 0) + 8 > availableLength {
            capacity -= 1; more = true
            width = spaces + trash + CGFloat(min(total, capacity)) * step + step + widgetTotal + (shownWidgets > 0 ? 12 : 0) + settings
        }
        apps = min(model.items.count, capacity)
        collections = min(model.collections.count, max(0, capacity - apps))
        links = min(model.quickLinks.count, max(0, capacity - apps - collections))
        widgets = shownWidgets; compact = isCompact; collapsedSpaces = collapsed; overflow = more
        showsTrash = showTrash; showsSettings = showSettings
        widgetWidth = widgetSide; widgetTotalWidth = widgetTotal; spacesWidth = spaces; trashWidth = trash; baseWidth = width
        hoverAllowance = apps == 0 ? 0 : hover
    }
}
