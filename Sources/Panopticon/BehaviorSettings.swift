import AppKit
import SwiftUI

extension SettingsView {
    var behavior: some View {
        VStack(spacing: 23) {
            card(L("Один Dock")) {
                row(
                    L("Заменить системный Dock"),
                    L("Добавляет закреплённые приложения из Dock macOS и скрывает системную панель"), $model.replaceDock
                )
                Button(L("Добавить приложения из Dock macOS")) { model.importDock() }.font(Studio.caption)
                Text(localization.status(dock.message)).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                Text(
                    L("При выходе из Panopticon прежние настройки Dock восстановятся. После аварийного завершения восстановить его можно этой кнопкой.")
                ).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                Button(L("Вернуть системный Dock")) {
                    model.replaceDock = false
                    dock.restore()
                }.font(.system(size: 11))
                if NSWorkspace.shared.runningApplications.contains(where: {
                    $0.bundleIdentifier?.lowercased().contains("dockspace") == true
                        || $0.localizedName == "Dockspace"
                }) {
                    Button(L("Закрыть Dockspace")) {
                        NSWorkspace.shared.runningApplications.first { $0.localizedName == "Dockspace" }?
                            .terminate()
                    }.font(.system(size: 11))
                }
            }
            card(L("Положение и видимость")) {
                Picker(L("Край экрана"), selection: $model.edge) {
                    ForEach(DockEdge.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }.id(localization.code).font(.system(size: 11))
                row(L("Показывать панель"), L("Также переключается сочетанием ⌃⌥D"), $model.barVisible)
                row(
                    L("Следовать за курсором"), L("Перемещать панель на экран, где находится курсор"),
                    $model.followMouse)
                row(
                    L("Корзина на панели"),
                    L("Перетаскивание закреплённой иконки сюда убирает ярлык; файл из Finder отправляется в Корзину"),
                    $model.showTrash)
                row(
                    L("Бейджи приложений"),
                    L("Считывать счётчики из системного Dock при разрешённом Универсальном доступе"),
                    $model.showBadges)
                if model.showBadges && !AX.trusted {
                    Button(L("Подключить Универсальный доступ…")) { AX.requestTrust() }.font(.system(size: 11))
                }
                Picker(L("Экран"), selection: $model.screenIndex) {
                    if model.screenIndex >= NSScreen.screens.count { Text(L("Выбранный экран недоступен")).tag(model.screenIndex) }
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        Text(screen.localizedName).tag(index)
                    }
                }.font(.system(size: 11)).id(displayRevision).disabled(model.followMouse)
                Text(L("Если выбранный экран временно недоступен, панель использует основной.")).font(Studio.caption).foregroundStyle(.secondary)
                row(
                    L("Автоматически скрывать"), L("Показывать после короткого наведения к краю экрана; обычные клики не вызывают панель"),
                    $model.autoHide)
                row(
                    L("Открытые приложения"), L("Незакреплённые видны до выхода. Правый клик → «Оставить в Dock» закрепляет их навсегда."),
                    $model.showRunning)
            }

            card(L("Окна при наведении")) {
                row(L("Показывать окна приложения"),
                    L("Задержи курсор на запущенном приложении и выбери нужное окно. Свёрнутые окна можно восстановить одним нажатием."),
                    $model.showWindowSwitcher)
                Text(L("Список окон использует Универсальный доступ. Снимки экрана и запись экрана не нужны. Вкладки внутри браузера остаются в самом браузере."))
                    .font(Studio.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.showWindowSwitcher && !AX.trusted {
                    Button(L("Подключить Универсальный доступ…")) { AX.requestTrust() }.font(Studio.caption)
                }
            }

            Button(L("Завершить Panopticon и восстановить Dock")) { NSApp.terminate(nil) }.font(.system(size: 11))
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
    }
}
