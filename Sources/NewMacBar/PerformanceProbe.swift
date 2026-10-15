import AppKit
import Darwin

struct ProcessMeasurement {
    let cpuSeconds: Double
    let residentBytes: Int64
    let footprintBytes: UInt64?
    static func read() -> ProcessMeasurement {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { values in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), values, &count)
            }
        }
        return ProcessMeasurement(cpuSeconds: user + system, residentBytes: Int64(usage.ru_maxrss), footprintBytes: status == KERN_SUCCESS ? info.phys_footprint : nil)
    }
}

/// Explicit developer probe. One sample before/after a calm interval; no periodic
/// disk writes or activation. Used in a separately identified QA bundle, never on
/// the user's existing settings. Does not run during an ordinary launch.
enum PerformanceProbe {
    static func startIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--performance-probe"), flag + 2 < arguments.count,
              let seconds = Double(arguments[flag + 1]), (30...3600).contains(seconds) else { return }
        let output = URL(fileURLWithPath: arguments[flag + 2])
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            let before = ProcessMeasurement.read(); let start = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                let after = ProcessMeasurement.read(); let elapsed = ProcessInfo.processInfo.systemUptime - start
                var report: [String: Any] = ["warmupSeconds": 15, "elapsedSeconds": elapsed, "cpuSeconds": after.cpuSeconds - before.cpuSeconds, "averageCPUPercentOfOneCore": (after.cpuSeconds - before.cpuSeconds) / elapsed * 100, "maximumResidentBytes": after.residentBytes]
                if let footprint = after.footprintBytes { report["physicalFootprintBytes"] = footprint }
                do { let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]); try data.write(to: output, options: .atomic); print("Local performance probe completed.") }
                catch { fputs("Could not write local performance probe.\n", stderr) }
                NSApp.terminate(nil)
            }
        }
    }
}
