import AppKit
import Darwin

/// The same harness can be compiled against the 0.5 baseline. This measures only
/// AppKit layout/render work, not a claim about real users, battery or 72-hour uptime.
func runPresentationBenchmark() {
    _ = NSApplication.shared
    let suite = "app.newmacbar.benchmark.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(
        [
            "/System/Library/CoreServices/Finder.app", "/System/Applications/Calendar.app",
            "/System/Applications/Music.app", "/System/Applications/System Settings.app",
        ], forKey: "pinned")
    let model = BarModel(defaults: defaults, observe: false)
    model.showRunning = false
    model.showBadges = false
    model.widget = "clock"
    model.secondaryWidget = "calendar"
    let bar = BarView(
        model: model, music: MusicController(), focus: FocusTimer(defaults: defaults),
        agenda: CalendarController())
    let panel = BarPanel(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 200),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    let root = PassthroughView()
    root.addSubview(bar.glass)
    root.addSubview(bar)
    panel.contentView = root
    var layout: [Double] = []
    var drawing: [Double] = []
    func measure(_ block: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
    for edge in DockEdge.allCases {
        model.edge = edge.rawValue
        let size = NSSize(width: bar.preferredWidth, height: bar.preferredHeight)
        panel.setContentSize(size)
        bar.frame = root.bounds
        bar.refresh()
        for index in 0..<300 {
            autoreleasepool {
                let value = measure { bar.refresh() }
                if index >= 20 { layout.append(value) }
                if index % 10 == 0, let bitmap = bar.bitmapImageRepForCachingDisplay(in: bar.bounds) {
                    let render = measure { bar.cacheDisplay(in: bar.bounds, to: bitmap) }
                    if index >= 20 { drawing.append(render) }
                }
            }
        }
    }
    func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))]
    }
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = [
        "scenario": "4 installed apps, 2 widgets, 4 edges, 280 warmed refreshes per edge",
        "layoutSamples": layout.count, "layoutMedianMS": percentile(layout, 0.5),
        "layoutP95MS": percentile(layout, 0.95), "drawSamples": drawing.count,
        "drawMedianMS": percentile(drawing, 0.5), "drawP95MS": percentile(drawing, 0.95),
        "maximumResidentBytes": usage.ru_maxrss,
    ]
    print(
        String(
            data: try! JSONSerialization.data(
                withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    panel.orderOut(nil)
}
