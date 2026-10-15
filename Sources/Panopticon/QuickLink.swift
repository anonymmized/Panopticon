import AppKit

struct QuickLink: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var kind: String
    var destination: String
    var symbol: String { kind == "folder" ? "folder.fill" : (kind == "file" ? "doc.fill" : "globe") }
    var url: URL? {
        if kind == "folder" || kind == "file" {
            return destination.hasPrefix("/") ? URL(fileURLWithPath: destination).standardizedFileURL : nil
        }
        guard let url = URL(string: destination), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
            url.host != nil
        else { return nil }
        return url
    }
}
