import Foundation
import SwiftUI

/// Stable identity preserves settings, Dock recovery and macOS privacy grants
/// across the NewMacBar → Panopticon rename. This is not a display name.
enum AppIdentity {
    static let preferencesDomain = "app.newmacbar.desktop"
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", russian = "ru"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L("Как в системе")
        case .english: return "English"
        case .russian: return "Русский"
        }
    }
}

/// Interpolations are separate from the lookup key. User names, paths and event
/// titles never become translation keys, and inserted text is never reinterpreted.
struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]
    init(stringLiteral value: String) { key = value; arguments = [] }
    init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key; arguments = stringInterpolation.arguments
    }
    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"; arguments.append(String(describing: value))
        }
    }
}

func L(_ message: LocalizedMessage) -> String { Localization.shared.text(message) }

final class Localization: ObservableObject {
    static let shared = Localization()
    static let didChange = Notification.Name("Panopticon.languageChanged")
    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]
    let catalogs: [String: [String: String]]
    @Published private(set) var language: AppLanguage
    private var localeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard,
         preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults; self.preferredLanguages = preferredLanguages
        language = AppLanguage(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "") ?? .system
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        var loaded: [String: [String: String]] = [:]
        for code in ["en", "ru"] {
            guard let url = bundle.url(forResource: code, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let catalog = try? JSONDecoder().decode([String: String].self, from: data) else {
                preconditionFailure("Missing Panopticon localization: \(code).json")
            }
            loaded[code] = catalog
        }
        catalogs = loaded
        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.language == .system else { return }
            self.objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
    deinit { if let localeObserver { NotificationCenter.default.removeObserver(localeObserver) } }
    static func resolve(_ language: AppLanguage, preferredLanguages: [String]) -> String {
        if language != .system { return language.rawValue }
        for tag in preferredLanguages {
            let code = tag.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first
            if code == "ru" { return "ru" }
            if code == "en" { return "en" }
        }
        return "en"
    }
    var code: String { Self.resolve(language, preferredLanguages: preferredLanguages()) }
    var locale: Locale { Locale(identifier: code == "ru" ? "ru_RU" : "en_US") }
    func setLanguage(_ value: AppLanguage) {
        guard value != language else { return }
        language = value; defaults.set(value.rawValue, forKey: "interfaceLanguage")
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
    func text(_ message: LocalizedMessage) -> String {
        let languageCode = code
        var template = catalogs[languageCode]?[message.key] ?? catalogs["en"]?[message.key] ?? message.key
        // Counts in source phrases share grammatical forms across every surface.
        let countWords = [("приложений", "apps", "app"), ("коллекций", "collections", "collection"),
                          ("ярлыков", "shortcuts", "shortcut"), ("элементов", "items", "item")]
        for (index, argument) in message.arguments.enumerated() {
            guard let count = Int(argument), count >= 0 else { continue }
            for (source, english, noun) in countWords where message.key.contains("{\(index)} " + source) {
                let category: String
                if languageCode == "ru" {
                    category = count % 10 == 1 && count % 100 != 11 ? "one"
                        : ((2...4).contains(count % 10) && !(12...14).contains(count % 100) ? "few" : "many")
                } else { category = count == 1 ? "one" : "other" }
                let word = catalogs[languageCode]?["plural.\(noun).\(category)"] ?? english
                template = template.replacingOccurrences(of: "{\(index)} " + (languageCode == "ru" ? source : english),
                                                         with: "{\(index)} " + word)
            }
        }
        return Self.render(template, arguments: message.arguments)
    }
    /// Scoped test override: no writes to the real preferences domain.
    func withTemporaryLanguage<T>(_ value: AppLanguage, _ body: () throws -> T) rethrows -> T {
        precondition(Thread.isMainThread)
        let previous = language; language = value
        defer { language = previous }
        return try body()
    }
    static func render(_ template: String, arguments: [String]) -> String {
        // A single pass avoids interpreting tokens contained in a user value.
        var result = ""; var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{", let end = template[index...].firstIndex(of: "}"),
               let n = Int(template[template.index(after: index)..<end]), arguments.indices.contains(n) {
                result += arguments[n]; index = template.index(after: end)
            } else { result.append(template[index]); index = template.index(after: index) }
        }
        return result
    }
    /// Only for controller-owned status messages, never user-authored content.
    func status(_ value: String) -> String {
        for catalog in catalogs.values {
            if let key = catalog.first(where: { $0.value == value })?.key {
                return catalogs[code]?[key] ?? value
            }
        }
        return value // OS errors retain the language supplied by macOS.
    }
}
