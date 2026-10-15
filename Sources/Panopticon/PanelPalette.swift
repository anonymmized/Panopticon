import AppKit

/// Semantic panel colors shared by rendering, themes and accessibility fallbacks.
struct PanelPalette {
    let gradient: [NSColor]
    let textScrim: NSColor
    let border: NSColor
    let innerRim: NSColor
    let solid: NSColor
    let accent: NSColor?
    static func resolve(_ theme: DockTheme, light: Bool) -> PanelPalette {
        values[theme == .glass ? (light ? "glassLight" : "glassDark") : theme.rawValue]!
    }
    private static let values: [String: PanelPalette] = [
        "glassDark": PanelPalette(gradient: [],
            textScrim: NSColor(calibratedRed: 0.054902, green: 0.062745, blue: 0.086275, alpha: 0.420000),
            border: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.160000), innerRim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.220000),
            solid: NSColor(calibratedRed: 0.109804, green: 0.117647, blue: 0.141176, alpha: 1.000000), accent: nil),
        "glassLight": PanelPalette(gradient: [],
            textScrim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.580000),
            border: NSColor(calibratedRed: 0.000000, green: 0.000000, blue: 0.000000, alpha: 0.120000), innerRim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.720000),
            solid: NSColor(calibratedRed: 0.949020, green: 0.956863, blue: 0.972549, alpha: 1.000000), accent: nil),
        "dark": PanelPalette(gradient: [NSColor(calibratedRed: 0.109804, green: 0.117647, blue: 0.141176, alpha: 0.760000), NSColor(calibratedRed: 0.062745, green: 0.070588, blue: 0.086275, alpha: 0.880000)],
            textScrim: NSColor(calibratedRed: 0.039216, green: 0.047059, blue: 0.062745, alpha: 0.480000),
            border: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.140000), innerRim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.180000),
            solid: NSColor(calibratedRed: 0.086275, green: 0.094118, blue: 0.113725, alpha: 1.000000), accent: nil),
        "light": PanelPalette(gradient: [NSColor(calibratedRed: 0.980392, green: 0.984314, blue: 0.992157, alpha: 0.800000), NSColor(calibratedRed: 0.909804, green: 0.925490, blue: 0.949020, alpha: 0.880000)],
            textScrim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.640000),
            border: NSColor(calibratedRed: 0.000000, green: 0.000000, blue: 0.000000, alpha: 0.120000), innerRim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.850000),
            solid: NSColor(calibratedRed: 0.956863, green: 0.964706, blue: 0.980392, alpha: 1.000000), accent: nil),
        "aurora": PanelPalette(gradient: [NSColor(calibratedRed: 0.419608, green: 0.250980, blue: 0.949020, alpha: 0.620000), NSColor(calibratedRed: 0.050980, green: 0.749020, blue: 0.701961, alpha: 0.580000)],
            textScrim: NSColor(calibratedRed: 0.047059, green: 0.062745, blue: 0.109804, alpha: 0.560000),
            border: NSColor(calibratedRed: 0.349020, green: 0.850980, blue: 0.749020, alpha: 0.280000), innerRim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.240000),
            solid: NSColor(calibratedRed: 0.101961, green: 0.133333, blue: 0.203922, alpha: 1.000000), accent: NSColor(calibratedRed: 0.349020, green: 0.850980, blue: 0.749020, alpha: 1.000000)),
        "electric": PanelPalette(gradient: [NSColor(calibratedRed: 0.050980, green: 0.450980, blue: 1.000000, alpha: 0.620000), NSColor(calibratedRed: 0.949020, green: 0.149020, blue: 0.749020, alpha: 0.560000)],
            textScrim: NSColor(calibratedRed: 0.047059, green: 0.054902, blue: 0.109804, alpha: 0.580000),
            border: NSColor(calibratedRed: 0.360784, green: 0.658824, blue: 1.000000, alpha: 0.300000), innerRim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.240000),
            solid: NSColor(calibratedRed: 0.098039, green: 0.117647, blue: 0.211765, alpha: 1.000000), accent: NSColor(calibratedRed: 0.360784, green: 0.658824, blue: 1.000000, alpha: 1.000000)),
        "sunset": PanelPalette(gradient: [NSColor(calibratedRed: 1.000000, green: 0.450980, blue: 0.200000, alpha: 0.600000), NSColor(calibratedRed: 0.850980, green: 0.149020, blue: 0.450980, alpha: 0.580000)],
            textScrim: NSColor(calibratedRed: 0.101961, green: 0.047059, blue: 0.078431, alpha: 0.580000),
            border: NSColor(calibratedRed: 1.000000, green: 0.580392, blue: 0.400000, alpha: 0.280000), innerRim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.220000),
            solid: NSColor(calibratedRed: 0.168627, green: 0.094118, blue: 0.133333, alpha: 1.000000), accent: NSColor(calibratedRed: 1.000000, green: 0.580392, blue: 0.400000, alpha: 1.000000)),
        "graphite": PanelPalette(gradient: [NSColor(calibratedRed: 0.219608, green: 0.227451, blue: 0.250980, alpha: 0.820000), NSColor(calibratedRed: 0.078431, green: 0.086275, blue: 0.101961, alpha: 0.900000)],
            textScrim: NSColor(calibratedRed: 0.054902, green: 0.058824, blue: 0.070588, alpha: 0.500000),
            border: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.180000), innerRim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.200000),
            solid: NSColor(calibratedRed: 0.125490, green: 0.133333, blue: 0.152941, alpha: 1.000000), accent: NSColor(calibratedRed: 0.780392, green: 0.803922, blue: 0.839216, alpha: 1.000000)),
        "frost": PanelPalette(gradient: [NSColor(calibratedRed: 0.850980, green: 0.949020, blue: 1.000000, alpha: 0.780000), NSColor(calibratedRed: 0.600000, green: 0.800000, blue: 1.000000, alpha: 0.720000)],
            textScrim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.680000),
            border: NSColor(calibratedRed: 0.149020, green: 0.450980, blue: 0.850980, alpha: 0.200000), innerRim: NSColor(calibratedRed: 1.000000, green: 1.000000, blue: 1.000000, alpha: 0.880000),
            solid: NSColor(calibratedRed: 0.921569, green: 0.956863, blue: 0.988235, alpha: 1.000000), accent: NSColor(calibratedRed: 0.121569, green: 0.435294, blue: 0.921569, alpha: 1.000000)),
    ]
}
