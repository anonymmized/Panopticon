import AppKit
import SwiftUI

extension SettingsView {
    var behavior: some View {
        VStack(spacing: 23) {
            card("Один Dock") {
                row(
                    "Заменить системный Dock",
                    "Добавляет закреплённые приложения из Dock macOS и скрывает системную панель", $model.replaceDock
                )
                Button("Добавить приложения из Dock macOS") { model.importDock() }.font(Studio.caption)
                Text(dock.message).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                Text(
                    "При выходе из NewMacBar прежние настройки Dock восстановятся. После аварийного завершения восстановить его можно этой кнопкой."
                ).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                Button("Вернуть системный Dock") {
                    model.replaceDock = false
                    dock.restore()
                }.font(.system(size: 11))
                if NSWorkspace.shared.runningApplications.contains(where: {
                    $0.bundleIdentifier?.lowercased().contains("dockspace") == true
                        || $0.localizedName == "Dockspace"
                }) {
                    Button("Закрыть Dockspace") {
                        NSWorkspace.shared.runningApplications.first { $0.localizedName == "Dockspace" }?
                            .terminate()
                    }.font(.system(size: 11))
                }
            }
            card("Положение и видимость") {
                Picker("Край экрана", selection: $model.edge) {
                    ForEach(DockEdge.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }.font(.system(size: 11))
                row("Показывать панель", "Также переключается сочетанием ⌃⌥D", $model.barVisible)
                row(
                    "Следовать за курсором", "Перемещать панель на экран, где находится курсор",
                    $model.followMouse)
                row(
                    "Корзина на панели",
                    "Перетаскивание закреплённой иконки сюда убирает ярлык; файл из Finder отправляется в Корзину",
                    $model.showTrash)
                row(
                    "Бейджи приложений",
                    "Считывать счётчики из системного Dock при разрешённом Универсальном доступе",
                    $model.showBadges)
                if model.showBadges && !AX.trusted {
                    Button("Подключить Универсальный доступ…") { AX.requestTrust() }.font(.system(size: 11))
                }
                Picker("Экран", selection: $model.screenIndex) {
                    if model.screenIndex >= NSScreen.screens.count { Text("Выбранный экран недоступен").tag(model.screenIndex) }
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        Text(screen.localizedName).tag(index)
                    }
                }.font(.system(size: 11)).id(displayRevision).disabled(model.followMouse)
                Text("Если выбранный экран временно недоступен, панель использует основной.").font(Studio.caption).foregroundStyle(.secondary)
                row(
                    "Автоматически скрывать", "Показывать после короткого наведения к краю экрана; обычные клики не вызывают панель",
                    $model.autoHide)
                row(
                    "Открытые приложения", "Незакреплённые видны до выхода. Правый клик → «Оставить в Dock» закрепляет их навсегда.",
                    $model.showRunning)
            }

            Button("Завершить NewMacBar и восстановить Dock") { NSApp.terminate(nil) }.font(.system(size: 11))
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
    }
}
