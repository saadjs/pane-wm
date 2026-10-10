import AppKit
import Observation
import PaneCore
import SwiftUI

/// The UI is a standard system button. Only shortcut capture needs application code.
struct ShortcutControl: View {
    let model: PaneModel
    let target: ShortcutTarget
    let name: String
    @State private var capture = ShortcutCapture()

    var body: some View {
        HStack(spacing: 6) {
            Button(capture.isRecording ? capture.prompt : model.shortcut(for: target)?.label ?? "Record") {
                capture.begin(
                    onRecordingChange: { model.isRecordingShortcut = $0 },
                    onCapture: { model.assign($0, to: target) }
                )
            }
            .disabled(model.isRecordingShortcut && !capture.isRecording)
            .help(capture.isRecording ? "Press a shortcut. Escape cancels." : "Record shortcut for \(name)")
            .accessibilityLabel("Shortcut for \(name): \(model.shortcut(for: target)?.label ?? "Not assigned")")
            Button { model.assign(nil, to: target) } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(model.shortcut(for: target) == nil || model.isRecordingShortcut)
            .help("Clear shortcut for \(name)")
            .accessibilityLabel("Clear shortcut for \(name)")
        }
        .onDisappear { capture.cancel() }
    }
}

@MainActor
@Observable
private final class ShortcutCapture {
    private(set) var isRecording = false
    private(set) var prompt = "Press shortcut…"
    @ObservationIgnored private var eventMonitor: Any?
    @ObservationIgnored private var focusObserver: NSObjectProtocol?
    @ObservationIgnored private var onRecordingChange: ((Bool) -> Void)?
    @ObservationIgnored private var onCapture: ((Shortcut) -> Void)?

    isolated deinit { cancel() }

    func begin(onRecordingChange: @escaping (Bool) -> Void, onCapture: @escaping (Shortcut) -> Void) {
        guard !isRecording, let window = NSApplication.shared.keyWindow else { return }
        self.onRecordingChange = onRecordingChange
        self.onCapture = onCapture
        prompt = "Press shortcut…"
        isRecording = true
        // Unregister Pane's hotkeys so an existing assignment can be recorded again.
        onRecordingChange(true)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self, weak window] event in
            guard let self else { return event }
            guard event.type == .keyDown, event.window === window else {
                self.cancel()
                return event
            }
            if event.keyCode == 53 { self.cancel(); return nil }
            if event.isARepeat { return nil }
            let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: Self.modifiers(event), keyLabel: Self.keyLabel(event))
            guard shortcut.isValid else {
                self.prompt = "Include ⌃, ⌥, or ⌘"
                NSSound.beep()
                return nil
            }
            let callback = self.onCapture
            self.cancel()
            callback?(shortcut)
            return nil
        }
        focusObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    func cancel() {
        guard isRecording else { return }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        eventMonitor = nil
        focusObserver = nil
        isRecording = false
        onRecordingChange?(false)
        onRecordingChange = nil
        onCapture = nil
    }

    private static func modifiers(_ event: NSEvent) -> UInt32 {
        var result: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.control) { result |= Shortcut.control }
        if flags.contains(.option) { result |= Shortcut.option }
        if flags.contains(.shift) { result |= Shortcut.shift }
        if flags.contains(.command) { result |= Shortcut.command }
        return result
    }

    private static func keyLabel(_ event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 76: "⌅", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        ]
        if let label = special[event.keyCode] { return label }
        let label = event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        guard !label.isEmpty, label.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return "Key \(event.keyCode)"
        }
        return label
    }
}
