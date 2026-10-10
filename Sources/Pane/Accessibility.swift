import AppKit
@preconcurrency import ApplicationServices

@MainActor
enum Accessibility {
    nonisolated static let checkArgument = "--check-accessibility"

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// A running process can keep a stale answer after its entry in the Accessibility list is
    /// removed and added again, so ask a fresh copy of Pane, which exits with the real answer.
    nonisolated static func isTrustedInFreshProcess() async -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }
        return await withCheckedContinuation { continuation in
            let check = Process()
            check.executableURL = executable
            check.arguments = [checkArgument]
            check.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try check.run() } catch { continuation.resume(returning: false) }
        }
    }

    /// Drops any entry left by a differently signed build (it shows as on but never matches), then
    /// asks macOS to list this build.
    static func requestAccess() {
        let reset = Process()
        reset.executableURL = URL(filePath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "sh.saad.pane"]
        reset.standardOutput = FileHandle.nullDevice
        reset.standardError = FileHandle.nullDevice
        if (try? reset.run()) != nil { reset.waitUntilExit() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.3)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(parent, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        (value(element, attribute) as? NSNumber)?.boolValue ?? false
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &result) == .success && result.boolValue
    }

    static func windows(_ application: AXUIElement) -> [AXUIElement] {
        let windows = value(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.filter {
            let role = value($0, kAXRoleAttribute) as? String
            let subrole = value($0, kAXSubroleAttribute) as? String
            return role == kAXWindowRole && (subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole)
        }
    }

    static func frame(_ window: AXUIElement) -> CGRect? {
        guard let positionValue = value(window, kAXPositionAttribute),
              let sizeValue = value(window, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let position = positionValue as! AXValue
        let size = sizeValue as! AXValue
        guard AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func move(_ window: AXUIElement, to point: CGPoint) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return set(window, kAXPositionAttribute, value)
    }

    static func resize(_ window: AXUIElement, to size: CGSize) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return set(window, kAXSizeAttribute, value)
    }

    static func raise(_ window: AXUIElement, application: AXUIElement) throws {
        if bool(window, kAXMinimizedAttribute) {
            guard set(window, kAXMinimizedAttribute, kCFBooleanFalse) == .success else {
                throw WindowControlError.message("This app couldn’t restore its minimized window.")
            }
        }
        if isSettable(window, kAXMainAttribute) { set(window, kAXMainAttribute, kCFBooleanTrue) }
        if isSettable(application, kAXFocusedWindowAttribute) { set(application, kAXFocusedWindowAttribute, window) }
        // Some apps (Calculator) reject AXRaise; activating the app still brings the window forward.
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

enum WindowControlError: LocalizedError {
    case message(String)
    case notTrusted
    var errorDescription: String? {
        switch self {
        case .message(let message): message
        case .notTrusted: "Pane needs Accessibility access."
        }
    }
}
