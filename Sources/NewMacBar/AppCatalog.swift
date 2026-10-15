import AppKit
import Combine

final class AppCatalog: ObservableObject {
    @Published private(set) var items: [DockItem] = []
    @Published private(set) var loading = false
    private var refreshed = Date.distantPast
    private let queue = DispatchQueue(label: "NewMacBar.app-catalog", qos: .userInitiated)
    func refresh(force: Bool = false) {
        guard !loading, force || Date().timeIntervalSince(refreshed) > 120 else { return }
        loading = true
        refreshed = Date()
        let systemApps = ["com.apple.Safari"].compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        queue.async { [weak self] in
            let manager = FileManager.default
            var urls = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")] + systemApps
            for path in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"] {
                guard
                    let enumerator = manager.enumerator(
                        at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
                else { continue }
                for case let url as URL in enumerator {
                    if url.pathExtension.lowercased() == "app" {
                        urls.append(url)
                        enumerator.skipDescendants()
                    } else if enumerator.level >= 2 {
                        enumerator.skipDescendants()
                    }
                }
            }
            var seen = Set<String>()
            let discovered = urls.map { $0.resolvingSymlinksInPath().standardizedFileURL }.filter { seen.insert($0.path).inserted }
            DispatchQueue.main.async {
                guard let self else { return }
                self.items = discovered.map { DockItem(url: $0) }.filter { $0.bundleID != nil }.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                self.loading = false
            }
        }
    }
    static func searchScore(_ query: String, in name: String) -> Int? {
        let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).filter {
            !$0.isWhitespace
        }
        let n = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).filter {
            !$0.isWhitespace
        }
        func score(_ q: String) -> Int? {
            if q.isEmpty || n.hasPrefix(q) { return 0 }
            if n.contains(q) { return 20 }
            var cursor = n.startIndex
            var gaps = 0
            for char in q {
                guard let index = n[cursor...].firstIndex(of: char) else { return nil }
                gaps += n.distance(from: cursor, to: index)
                cursor = n.index(after: index)
            }
            return 40 + gaps
        }
        let russian = Array("йцукенгшщзхъфывапролджэячсмитьбю")
        let latin = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.")
        let toLatin = Dictionary(uniqueKeysWithValues: zip(russian, latin))
        let toRussian = Dictionary(uniqueKeysWithValues: zip(latin, russian))
        let variants = [q, String(q.map { toLatin[$0] ?? $0 }), String(q.map { toRussian[$0] ?? $0 })]
        return variants.enumerated().compactMap { index, value in
            score(value).map { $0 + (index == 0 ? 0 : 8) }
        }.min()
    }

}
