import AppKit

struct AppCollection: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var symbol = "square.grid.2x2.fill"
    var paths: [String] = []
    var items: [DockItem] {
        paths.map { DockItem(url: URL(fileURLWithPath: $0)) }.filter {
            $0.url.pathExtension.lowercased() == "app" && $0.bundleID != nil
                && FileManager.default.fileExists(atPath: $0.id)
        }
    }
}
