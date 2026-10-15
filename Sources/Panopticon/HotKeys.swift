import Carbon
import AppKit

/// Global hotkeys via Carbon — works without Accessibility permission.
final class HotKeys {
    static let shared = HotKeys()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installed = false
    private var localMonitor: Any?
    private var combinations: [UInt32: (UInt16, NSEvent.ModifierFlags)] = [:]
    private var lastTriggers: [UInt32: Date] = [:]

    static let controlOption = UInt32(controlKey | optionKey)
    static let digitKeys: [Int] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    /// Returns an id for `unregister`, or nil when another app already owns the combination.
    @discardableResult
    func register(_ keyCode: Int, modifiers: UInt32 = controlOption, handler: @escaping () -> Void) -> UInt32? {
        installHandler()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4644_4F43), id: id) // 'FDOC'
        guard RegisterEventHotKey(UInt32(keyCode), modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref) == noErr,
              let ref else { return nil }
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        combinations[id] = (UInt16(keyCode), flags)
        handlers[id] = handler
        refs[id] = ref
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil; combinations[id] = nil; lastTriggers[id] = nil
    }

    private func trigger(_ id: UInt32) {
        guard Date().timeIntervalSince(lastTriggers[id] ?? .distantPast) > 0.2 else { return }
        lastTriggers[id] = Date(); handlers[id]?()
    }
    private func installHandler() {
        guard !installed else { return }
        installed = true
        // AppKit also receives targeted key events while our own settings/search is active.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])
            if let id = self.combinations.first(where: { $0.value.0 == event.keyCode && $0.value.1 == flags })?.key {
                self.trigger(id); return nil
            }
            return event
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            guard let event,
                  GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID) == noErr,
                  hotKeyID.signature == 0x4644_4F43 else { return OSStatus(eventNotHandledErr) }
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeys.shared.trigger(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
