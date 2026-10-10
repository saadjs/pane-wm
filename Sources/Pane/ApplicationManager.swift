import AppKit
import PaneCore

@MainActor
final class ApplicationManager {
    private var windowOrder: [pid_t: [AXUIElement]] = [:]

    func activate(_ binding: AppBinding) async throws {
        let workspace = NSWorkspace.shared
        var runningURL: URL?
        if let running = workspace.runningApplications.first(where: { $0.bundleIdentifier == binding.bundleIdentifier }) {
            let wasFocused = running.isActive
            runningURL = running.bundleURL
            let application = Accessibility.application(running.processIdentifier)
            let trusted = Accessibility.isTrusted

            if trusted {
                let windows = orderedWindows(for: running, application: application)
                let focused = Accessibility.element(application, kAXFocusedWindowAttribute)
                let target: AXUIElement?
                if wasFocused, windows.count > 1 {
                    let index = focused.flatMap { current in windows.firstIndex { CFEqual($0, current) } } ?? -1
                    target = windows[(index + 1) % windows.count]
                } else if wasFocused, windows.count == 1,
                          !Accessibility.bool(windows[0], kAXMinimizedAttribute) {
                    return
                } else {
                    target = focused.flatMap { current in windows.first { CFEqual($0, current) } }
                        ?? windows.first { !Accessibility.bool($0, kAXMinimizedAttribute) }
                        ?? windows.first
                }
                if let target {
                    running.unhide()
                    try Accessibility.raise(target, application: application)
                    if wasFocused { return }
                    // Pane is a background app, so macOS ignores NSRunningApplication.activate().
                    // Opening the app through Launch Services below brings it forward reliably.
                }
            }

            // Reopening an app with no windows lets the app create its usual default window.
            if wasFocused, !trusted {
                throw WindowControlError.message("Allow Accessibility access to restore and cycle app windows.")
            }
        }

        guard let url = runningURL ?? workspace.urlForApplication(withBundleIdentifier: binding.bundleIdentifier) else {
            throw WindowControlError.message("\(binding.name) could not be found. Add it again in settings.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await workspace.openApplication(at: url, configuration: configuration)
    }

    private func orderedWindows(for running: NSRunningApplication, application: AXUIElement) -> [AXUIElement] {
        let livePIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        windowOrder = windowOrder.filter { livePIDs.contains($0.key) }
        let current = Accessibility.windows(application)
        // AXWindows can reorder when focus changes. Preserve order to avoid toggling only two windows.
        var ordered = (windowOrder[running.processIdentifier] ?? []).filter { old in current.contains { CFEqual(old, $0) } }
        ordered.append(contentsOf: current.filter { new in !ordered.contains { CFEqual(new, $0) } })
        windowOrder[running.processIdentifier] = ordered
        return ordered
    }
}
