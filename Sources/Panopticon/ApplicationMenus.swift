import AppKit

/// Standard responder-chain commands are required for text input, including
/// Cmd+V and tools/input methods that insert Unicode via the pasteboard.
enum ApplicationMenus {
    static func addEditing(to main: NSMenu) {
        let item = NSMenuItem(title: L("Правка"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L("Правка"))
        menu.addItem(withTitle: L("Отменить"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: L("Повторить"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Вырезать"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: L("Скопировать"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: L("Вставить"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: L("Выбрать всё"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        item.submenu = menu; main.addItem(item)
    }
    static func reviewMenu() -> NSMenu {
        let main = NSMenu(); let item = NSMenuItem(); let app = NSMenu()
        app.addItem(withTitle: L("Завершить проверку"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = app; main.addItem(item); addEditing(to: main); return main
    }
}
