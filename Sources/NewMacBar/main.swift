import AppKit

if CommandLine.arguments.contains("--self-test") {
    runSelfTests()
} else if CommandLine.arguments.contains("--panel-self-test") {
    runPanelSelfTests()
} else if CommandLine.arguments.contains("--ui-benchmark") {
    runPresentationBenchmark()
} else if CommandLine.arguments.contains("--ui-review") {
    UIReviewHarness.run()
} else if CommandLine.arguments.contains("--visibility-state") {
    exit(DockVisibilityDiagnostics.query())
} else if CommandLine.arguments.contains("--restore-system-dock") {
    exit(SessionLifecycle.restoreFromCommandLine())
} else if CommandLine.arguments.contains("--diagnostics") {
    // Read-only local report: no permission request, file path or event contents.
    print(LocalDiagnostics.commandReport())
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
