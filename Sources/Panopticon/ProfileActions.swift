import AppKit

extension BarModel {
    var launcherShortcutLabel: String {
        [
            "controlOptionSpace": L("⌃⌥ пробел"), "commandShiftSpace": L("⌘⇧ пробел"),
            "optionShiftSpace": L("⌥⇧ пробел"),
        ][launcherShortcutChoice] ?? L("⌃⌥ пробел")
    }
    var calendarTarget: LaunchTarget? {
        ActionRouter.calendarTarget(
            kind: calendarDestination, appPath: calendarAppPath, webURL: calendarWebURL)
    }
    var calendarAppName: String {
        calendarDestination == "web"
            ? URL(string: calendarWebURL)?.host ?? L("Веб-календарь")
            : (calendarDestination == "app"
                ? FileManager.default.displayName(atPath: calendarAppPath).replacingOccurrences(
                    of: ".app", with: "") : L("Календарь macOS"))
    }
    var widgetKinds: [String] {
        var result: [String] = []
        for kind in [widget, secondaryWidget] where kind != "none" && !result.contains(kind) {
            result.append(kind)
        }
        return result
    }
    func openCalendar() { ActionRouter.open(calendarTarget) }
    @discardableResult func addQuickLink(name: String, kind: String, destination: String) -> Bool {
        let link = QuickLink(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind,
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines))
        guard ["folder", "web", "file"].contains(kind), !link.name.isEmpty, link.url != nil,
            !quickLinks.contains(where: { $0.kind == link.kind && $0.destination == link.destination })
        else { return false }
        quickLinks.append(link)
        save()
        return true
    }
    @discardableResult func updateQuickLink(_ link: QuickLink) -> Bool {
        var updated = link
        updated.name = SettingsRules.label(updated.name)
        guard !updated.name.isEmpty, updated.url != nil, ["web", "folder", "file"].contains(updated.kind),
            !quickLinks.contains(where: {
                $0.id != link.id && $0.kind == link.kind && $0.destination == link.destination
            }),
            let i = quickLinks.firstIndex(where: { $0.id == link.id })
        else { return false }
        quickLinks[i] = updated
        save()
        return true
    }
    func moveQuickLink(_ id: String, by offset: Int) {
        guard let i = quickLinks.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(0, i + offset), quickLinks.count - 1)
        if target != i {
            quickLinks.swapAt(i, target)
            save()
        }
    }
    @discardableResult func renameProfile(_ id: String, to name: String) -> Bool {
        let name = SettingsRules.label(name)
        guard !name.isEmpty, let i = profiles.firstIndex(where: { $0.id == id }),
            !profiles.contains(where: {
                $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            })
        else { return false }
        profiles[i].name = name
        save()
        return true
    }
    func updateProfile(_ id: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i] = DockProfile(
            id: id, name: profiles[i].name, pinned: pinned.map(\.id), collections: collections,
            links: quickLinks, appearance: .init(self))
        save()
    }
    var matchingProfileID: String? {
        profiles.first {
            $0.pinned == pinned.map(\.id) && $0.collections == collections && $0.links == quickLinks
                && $0.appearance == ProfileAppearance(self)
        }?.id
    }
    func removeQuickLink(_ id: String) {
        quickLinks.removeAll { $0.id == id }
        save()
    }
    func saveProfile(name: String) {
        let name = SettingsRules.label(name)
        guard !name.isEmpty else { return }
        let profile = DockProfile(
            name: name, pinned: pinned.map(\.id), collections: collections, links: quickLinks,
            appearance: .init(self))
        if let index = profiles.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            var replacement = profile
            replacement.id = profiles[index].id
            profiles[index] = replacement
        } else {
            profiles.append(profile)
        }
        save()
    }
    func applyProfile(_ profile: DockProfile) {
        batch {
            pinned = profile.pinned.filter {
                FileManager.default.fileExists(atPath: $0)
                    && Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier != nil
            }.map { DockItem(url: URL(fileURLWithPath: $0)) }
            collections = profile.collections
            quickLinks = profile.links
            profile.appearance.sanitized().apply(to: self)
        }
    }
    func deleteProfile(_ id: String) {
        profiles.removeAll { $0.id == id }
        save()
    }
    var matchingPreset: String? {
        guard iconSize == 36, iconSpacing == 8, cornerRadius == 20, hoverStyle == "lift" else { return nil }
        if theme == "light" && widgetAccent == "blue" && opacity == 0.22 { return "frost" }
        if theme == "dark" && widgetAccent == "mint" && magnification == 1.4 && hoverGlow { return "aurora" }
        if theme == "dark" && widgetAccent == "violet" && magnification == 1.55 && hoverLift == 10 {
            return "electric"
        }
        if theme == "dark" && widgetAccent == "neutral" && magnification == 1.2 && !hoverGlow {
            return "graphite"
        }
        return nil
    }
    func applyPreset(_ preset: String) {
        batch {
            iconSize = 36
            iconSpacing = 8
            magnification = 1.4
            hoverLift = 7
            hoverStyle = "lift"
            cornerRadius = 20
            opacity = 0.1
            hoverGlow = true
            launchStyle = "bounce"
            theme = "dark"
            if preset == "aurora" {
                widgetAccent = "mint"
                widgetOpacity = 0.22
            }
            if preset == "electric" {
                widgetAccent = "violet"
                widgetOpacity = 0.4
                hoverLift = 10
                magnification = 1.55
            }
            if preset == "graphite" {
                widgetAccent = "neutral"
                widgetOpacity = 0.16
                hoverGlow = false
                hoverLift = 3
                magnification = 1.2
            }
            if preset == "frost" {
                theme = "light"
                widgetAccent = "blue"
                widgetOpacity = 0.2
                opacity = 0.22
                hoverGlow = false
            }
        }
    }
}
