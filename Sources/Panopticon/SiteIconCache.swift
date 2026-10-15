import AppKit

/// Website icons come only from the site the user pinned, never a favicon proxy.
final class SiteIconCache {
    static let shared = SiteIconCache()
    var onChange: (() -> Void)?
    private var images: [String: NSImage] = [:]
    private var requested = Set<String>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: config)
    }()
    func image(for url: URL) -> NSImage? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host else { return nil }
        if let image = images[host] { return image }
        if requested.insert(host).inserted { request(host: host, index: 0) }
        return nil
    }
    private func request(host: String, index: Int) {
        let paths = ["/apple-touch-icon.png", "/favicon.ico"]
        guard index < paths.count else { return }
        var components = URLComponents(); components.scheme = "https"; components.host = host; components.path = paths[index]
        guard let url = components.url else { return }
        session.dataTask(with: url) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data, data.count < 2_000_000, (response as? HTTPURLResponse)?.statusCode == 200,
                   let image = NSImage(data: data), image.size.width >= 16 {
                    self.images[host] = image; self.onChange?()
                } else { self.request(host: host, index: index + 1) }
            }
        }.resume()
    }
}
