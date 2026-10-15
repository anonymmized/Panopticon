import AppKit

private final class TestDrag: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = [.copy, .move]
    var draggingLocation = NSPoint.zero
    var draggedImageLocation = NSPoint.zero
    var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    deinit { draggingPasteboard.releaseGlobally() }
}

func runDragDropTests(bar: BarView, model: BarModel, panel: NSWindow) {
    model.edge = "bottom"; model.showSpaces = false; model.showTrash = false
    model.pinned = [DockItem(url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))]
    model.quickLinks = []; model.save(); bar.refresh()
    func drop(_ url: URL) -> Bool {
        let drag = TestDrag(); drag.draggingDestinationWindow = panel
        drag.draggingLocation = NSPoint(x: bar.barRect.maxX - 2, y: bar.barRect.midY)
        drag.draggingPasteboard.writeObjects([url as NSURL])
        _ = bar.draggingEntered(drag)
        let result = bar.performDragOperation(drag); bar.refresh(); return result
    }
    precondition(drop(URL(fileURLWithPath: "/System/Applications/Calendar.app")) && model.pinned.count == 2,
                 "External app pasteboard adds application")
    precondition(drop(URL(fileURLWithPath: "/private/tmp")) && model.quickLinks.last?.kind == "folder",
                 "External folder pasteboard adds stack")
    precondition(drop(URL(string: "https://example.com")!) && model.quickLinks.last?.kind == "web",
                 "External web pasteboard adds a website")
    precondition(!drop(URL(fileURLWithPath: "/private/tmp/Panopticon-missing-bundle.app")), "Invalid bundle drop must be rejected")
    model.showTrash = true; bar.refresh()
    let trash = (bar.accessibilityChildren() as? [BarAccessibilityButton])!.first { $0.accessibilityLabel() == L("Корзина") }!
    let screen = trash.accessibilityFrame()
    let drag = TestDrag(); drag.draggingDestinationWindow = panel; drag.draggingSource = bar
    drag.draggingLocation = panel.convertPoint(fromScreen: NSPoint(x: screen.midX, y: screen.midY))
    let removed = model.pinned[0]
    drag.draggingPasteboard.setString(removed.id, forType: NSPasteboard.PasteboardType("app.panopticon.item"))
    _ = bar.draggingEntered(drag)
    precondition(bar.performDragOperation(drag) && !model.pinned.contains(removed), "Internal trash drop removes shortcut")
    precondition(FileManager.default.fileExists(atPath: removed.id), "Internal trash drop must not delete application")
    print("PASS: AppKit app/folder/web drops, invalid bundles and shortcut-only trash drop")
}
