import AppKit

/// Scoped panel mutations. These operations never delete source files.
enum PanelActions {
    static let item = NSPasteboard.PasteboardType("app.panopticon.item")
    static let link = NSPasteboard.PasteboardType("app.newmacbar.link")
    static let collection = NSPasteboard.PasteboardType("app.newmacbar.collection")

    static func importSystemDock(model: BarModel) {
        model.importDock()
    }
    static func moveLink(_ id: String, toSpace target: String, model: BarModel) -> Bool {
        guard target != model.selectedSpaceID,
            let index = model.spaces.firstIndex(where: { $0.id == target }),
            let link = model.quickLinks.first(where: { $0.id == id }),
            !model.spaces[index].links.contains(where: {
                $0.destination == link.destination && $0.kind == link.kind
            })
        else { return false }
        model.batch {
            model.spaces[index].links.append(link)
            model.removeQuickLink(id)
        }
        return true
    }
    static func moveCollection(_ id: String, toSpace target: String, model: BarModel) -> Bool {
        guard target != model.selectedSpaceID,
            let index = model.spaces.firstIndex(where: { $0.id == target }),
            let group = model.collections.first(where: { $0.id == id }),
            !model.spaces[index].collections.contains(where: { $0.id == id })
        else { return false }
        model.batch {
            model.spaces[index].collections.append(group)
            model.removeCollection(id)
        }
        return true
    }
    static func reorderLink(_ id: String, before target: Int, model: BarModel) -> Bool {
        guard let index = model.quickLinks.firstIndex(where: { $0.id == id }) else { return false }
        var links = model.quickLinks
        let value = links.remove(at: index)
        links.insert(value, at: min(max(0, target - (index < target ? 1 : 0)), links.count))
        guard links != model.quickLinks else { return false }
        model.batch { model.quickLinks = links }
        return true
    }
    static func reorderCollection(_ id: String, before target: Int, model: BarModel) -> Bool {
        guard let index = model.collections.firstIndex(where: { $0.id == id }) else { return false }
        var groups = model.collections
        let value = groups.remove(at: index)
        groups.insert(value, at: min(max(0, target - (index < target ? 1 : 0)), groups.count))
        guard groups != model.collections else { return false }
        model.batch { model.collections = groups }
        return true
    }
    static func bind(_ space: BarSpace, desktop: Int?, model: BarModel) {
        if let desktop, let other = model.spaces.first(where: { $0.desktop == desktop && $0.id != space.id })
        {
            let alert = NSAlert()
            alert.messageText = L("Изменить привязку рабочего стола?")
            alert.informativeText =
                L("Стол \(desktop) связан с «\(other.name)». Он будет связан с «\(space.name)».")
            alert.addButton(withTitle: L("Перепривязать"))
            alert.addButton(withTitle: L("Отмена"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        model.bindSpace(space.id, desktop: desktop)
    }
}
