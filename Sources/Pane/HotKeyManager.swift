import Carbon
import PaneCore

enum ShortcutTarget: Hashable {
    case app(UUID)
    case window(WindowAction)
}

/// HIToolbox is isolated here: SwiftUI keyboardShortcut applies only inside an app.
@MainActor
final class HotKeyManager {
    private var handler: EventHandlerRef?
    private var references: [EventHotKeyRef] = []
    private var targets: [UInt32: ShortcutTarget] = [:]
    var onTrigger: ((ShortcutTarget) -> Void)?

    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    func register(_ bindings: [(ShortcutTarget, Shortcut)]) -> [ShortcutTarget: String] {
        unregister()
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetEventDispatcherTarget(),
                { _, event, context in
                    guard let event, let context else { return OSStatus(eventNotHandledErr) }
                    var identifier = EventHotKeyID()
                    let status = GetEventParameter(
                        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                        nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
                    )
                    guard status == noErr else { return status }
                    // The system event dispatcher calls this on the main event loop.
                    return MainActor.assumeIsolated {
                        let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
                        guard identifier.signature == 0x50414E45,
                              let target = manager.targets[identifier.id] else { return OSStatus(eventNotHandledErr) }
                        manager.onTrigger?(target)
                        return noErr
                    }
                },
                1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler
            )
            guard status == noErr else {
                return Dictionary(uniqueKeysWithValues: bindings.map { ($0.0, "Couldn’t start keyboard shortcuts (\(status)).") })
            }
        }

        var errors: [ShortcutTarget: String] = [:]
        let systemShortcuts = Self.enabledSystemShortcuts()
        for (index, binding) in bindings.enumerated() {
            let (target, shortcut) = binding
            guard shortcut.isValid else {
                errors[target] = "Use Control, Option, or Command with a key."
                continue
            }
            let id = UInt32(index + 1)
            var reference: EventHotKeyRef?
            var status = register(shortcut, id: id, options: OptionBits(kEventHotKeyExclusive), &reference)
            // macOS keeps its own shortcuts reserved even while they're switched off (⌃1 is
            // "Switch to Desktop 1"), which blocks an exclusive claim. A shared one still fires.
            if status == eventHotKeyExistsErr {
                status = register(shortcut, id: id, options: 0, &reference)
            }
            if status == noErr, let reference {
                references.append(reference)
                targets[id] = target
                // A shared claim succeeds even when macOS acts on the same keys, so check its list.
                if systemShortcuts.contains(where: { $0.keyCode == shortcut.keyCode && $0.modifiers == shortcut.modifiers }) {
                    errors[target] = "macOS also uses this shortcut. Turn it off in Keyboard settings or choose another."
                }
            } else {
                errors[target] = status == eventHotKeyExistsErr
                    ? "This shortcut is already in use by macOS or another app."
                    : "macOS couldn’t register this shortcut (\(status))."
            }
        }
        return errors
    }

    /// Shortcuts macOS itself currently acts on (Mission Control, Spotlight, screenshots…).
    private static func enabledSystemShortcuts() -> [(keyCode: UInt32, modifiers: UInt32)] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled as String] as? Bool == true,
                  let keyCode = entry[kHISymbolicHotKeyCode as String] as? UInt32,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? UInt32 else { return nil }
            // The Fn bit is implicit on arrow, navigation and function keys. On any other key it
            // means a Globe-key shortcut, which a Pane shortcut can't collide with.
            if modifiers & fnModifier != 0, !fnKeyCodes.contains(keyCode) { return nil }
            return (keyCode, modifiers & Shortcut.supportedModifiers)
        }
    }

    private static let fnModifier: UInt32 = 1 << 17
    private static let fnKeyCodes: Set<UInt32> = [
        123, 124, 125, 126, 115, 116, 117, 119, 121,
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    private func register(
        _ shortcut: Shortcut, id: UInt32, options: OptionBits, _ reference: inout EventHotKeyRef?
    ) -> OSStatus {
        RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x50414E45, id: id),
            GetEventDispatcherTarget(), options, &reference
        )
    }

    func unregister() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        targets.removeAll()
    }
}
