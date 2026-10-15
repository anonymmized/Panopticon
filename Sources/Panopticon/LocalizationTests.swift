import Foundation

func runLocalizationTests() {
    let suite = "app.panopticon.localization-test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("invalid", forKey: "interfaceLanguage")
    let localizer = Localization(defaults: defaults, preferredLanguages: { ["fr-FR", "ru-RU", "en-US"] })
    precondition(localizer.language == .system && localizer.code == "ru", "Normalize language and honor preferred order")
    precondition(Localization.resolve(.system, preferredLanguages: ["de-DE"]) == "en", "English fallback")
    precondition(Localization.resolve(.system, preferredLanguages: ["en-GB", "ru"]) == "en", "Prefer first supported language")
    precondition(Localization.resolve(.russian, preferredLanguages: ["en"]) == "ru", "Explicit language overrides system")
    let english = localizer.catalogs["en"]!; let russian = localizer.catalogs["ru"]!
    precondition(english.count > 350 && Set(english.keys) == Set(russian.keys), "Complete matching catalogs")
    func tokens(_ value: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"\{[0-9]+\}"#)
        return pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
            String(value[Range($0.range, in: value)!])
        }.sorted()
    }
    for (key, value) in english {
        precondition(!value.isEmpty && tokens(key) == tokens(value) && tokens(key) == tokens(russian[key]!), "Preserve interpolation tokens: \(key)")
        precondition(value.range(of: #"[А-Яа-яЁё]"#, options: .regularExpression) == nil, "Untranslated English entry: \(key)")
    }
    localizer.setLanguage(.english)
    precondition(localizer.text("Настройки…") == "Settings…", "English menu translation")
    precondition(localizer.text("\(1) приложений") == "1 app", "English singular")
    let name = "Проект {1} — 100% 🚀"
    precondition(localizer.text("Открыть \(name)") == "Open \(name)", "Preserve user data without recursive interpolation")
    precondition(localizer.text("\(2) приложений · \(3) коллекций · \(4) ярлыков") == "2 apps · 3 collections · 4 shortcuts", "Multiple interpolations")
    precondition(localizer.status("Системный Dock восстановлен.") == "System Dock restored.", "Controller status updates")
    let reloaded = Localization(defaults: defaults, preferredLanguages: { ["ru"] })
    precondition(reloaded.language == .english && reloaded.code == "en", "Persist language independently of model")
    localizer.setLanguage(.russian)
    precondition(localizer.text("Настройки…") == "Настройки…", "Russian menu translation")
    precondition(localizer.text("\(1) приложений") == "1 приложение", "Russian singular")
    precondition(localizer.text("\(2) приложений") == "2 приложения", "Russian few")
    precondition(localizer.text("\(11) приложений") == "11 приложений", "Russian teens")
    precondition(localizer.text("\(21) приложений") == "21 приложение", "Russian compound singular")
    precondition(localizer.locale.identifier == "ru_RU", "Localized dates")
    precondition(localizer.text("Открыть \(name)") == "Открыть \(name)", "Russian interpolation")
    precondition(AppIdentity.preferencesDomain == "app.newmacbar.desktop", "Keep existing settings and permissions identity")
    for (language, expected) in [(AppLanguage.english, "Appearance"), (.russian, "Внешний вид")] {
        Localization.shared.withTemporaryLanguage(language) {
            precondition(SettingsSection.all.first { $0.id == "appearance" }?.title == expected, "Settings navigation titles must not cache the previous language")
        }
    }
    print("PASS: bilingual catalogs, fallback, persistence, interpolation and stable application identity")
}
