import AppKit
import Carbon

final class GlobalShortcut {
    var action: (() -> Void)?
    private var localMonitor: Any?
    private var lastTrigger = Date.distantPast
    private var keyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var registered = false
    init(choice: String, action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                var hotKey = EventHotKeyID()
                guard let event,
                    GetEventParameter(
                        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey) == noErr,
                    hotKey.signature == 0x4E4D_4252, hotKey.id == 1
                else { return OSStatus(eventNotHandledErr) }
                guard let context else { return OSStatus(eventNotHandledErr) }
                Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().trigger()
                return noErr
            }, 1, &event, context, &handlerRef)
        let modifiers =
            choice == "commandShiftSpace"
            ? UInt32(cmdKey | shiftKey)
            : (choice == "optionShiftSpace" ? UInt32(optionKey | shiftKey) : UInt32(controlKey | optionKey))
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let desired: NSEvent.ModifierFlags =
                choice == "commandShiftSpace"
                ? [.command, .shift]
                : (choice == "optionShiftSpace" ? [.option, .shift] : [.control, .option])
            let actual = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == UInt16(kVK_Space), actual == desired {
                self?.trigger()
                return nil
            }
            return event
        }
        if status == noErr {
            registered =
                RegisterEventHotKey(
                    UInt32(kVK_Space), modifiers, EventHotKeyID(signature: 0x4E4D_4252, id: 1),
                    GetEventDispatcherTarget(), 0, &keyRef) == noErr
        }
    }
    private func trigger() {
        guard Date().timeIntervalSince(lastTrigger) > 0.2 else { return }
        lastTrigger = Date()
        action?()
    }
    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let keyRef { UnregisterEventHotKey(keyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
