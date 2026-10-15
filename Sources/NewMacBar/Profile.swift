import Foundation

struct DockProfile: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var pinned: [String]
    var collections: [AppCollection]
    var links: [QuickLink]
    var appearance: ProfileAppearance
}

struct ProfileAppearance: Codable, Equatable {
    var iconSize: Double
    var spacing: Double
    var opacity: Double
    var radius: Double
    var magnification: Double
    var lift: Double
    var bottom: Double
    var theme: String
    var accent: String
    var hover: String
    var launch: String
    var indicator: String
    var widget: String
    var secondaryWidget: String
    var widgetStyle: String
    var widgetWidth: Double
    var widgetOpacity: Double
    var glow: Bool
    var clockFormat: String?
    var clockSeconds: Bool?
    var timerMinutes: Double?
    var labels: Bool?
    var separator: Bool?
    var settingsButton: Bool?
    var showRunning: Bool?
    var autoHide: Bool?
    var reduceMotion: Bool?
    var motionMode: String?
    var edge: String?
    var showSpaces: Bool?
    var showTrash: Bool?
    init(_ model: BarModel) {
        edge = model.edge; showSpaces = model.showSpaces; showTrash = model.showTrash
        iconSize = model.iconSize; spacing = model.iconSpacing; opacity = model.opacity; radius = model.cornerRadius
        magnification = model.magnification; lift = model.hoverLift; bottom = model.bottomOffset
        theme = model.theme; accent = model.widgetAccent; hover = model.hoverStyle; launch = model.launchStyle
        indicator = model.indicatorStyle; widget = model.widget; secondaryWidget = model.secondaryWidget
        widgetStyle = model.widgetStyle; widgetWidth = model.widgetWidth; widgetOpacity = model.widgetOpacity; glow = model.hoverGlow
        clockFormat = model.clockFormat; clockSeconds = model.clockSeconds; timerMinutes = model.timerMinutes
        labels = model.showLabels; separator = model.showSeparator; settingsButton = model.showSettingsButton; showRunning = model.showRunning; autoHide = model.autoHide; reduceMotion = model.reduceMotion
        motionMode = model.motionMode
    }
    func apply(to model: BarModel) {
        if let edge { model.edge = edge }; if let showSpaces { model.showSpaces = showSpaces }; if let showTrash { model.showTrash = showTrash }
        model.iconSize = iconSize; model.iconSpacing = spacing; model.opacity = opacity; model.cornerRadius = radius
        model.magnification = magnification; model.hoverLift = lift; model.bottomOffset = bottom
        model.theme = theme; model.widgetAccent = accent; model.hoverStyle = hover; model.launchStyle = launch
        model.indicatorStyle = indicator; model.widget = widget; model.secondaryWidget = secondaryWidget
        model.widgetStyle = widgetStyle; model.widgetWidth = widgetWidth; model.widgetOpacity = widgetOpacity; model.hoverGlow = glow
        if let clockFormat { model.clockFormat = clockFormat }; if let clockSeconds { model.clockSeconds = clockSeconds }
        if let timerMinutes { model.timerMinutes = timerMinutes }; if let labels { model.showLabels = labels }
        if let separator { model.showSeparator = separator }; if let settingsButton { model.showSettingsButton = settingsButton }
        if let showRunning { model.showRunning = showRunning }; if let autoHide { model.autoHide = autoHide }; if let reduceMotion { model.reduceMotion = reduceMotion }
        if let motionMode { model.motionMode = motionMode }
        else if let reduceMotion { model.motionMode = reduceMotion ? "reduced" : "system" }
    }
}
