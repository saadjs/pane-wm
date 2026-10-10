import SwiftUI

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains(Accessibility.checkArgument) {
            exit(AXIsProcessTrusted() ? 0 : 1)
        }
        PaneApp.main()
    }
}

struct PaneApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            PaneMenu(model: delegate.model) { delegate.showSettings() }
        } label: {
            Image(systemName: delegate.model.isTrusted ? "rectangle.lefthalf.inset.filled" : "exclamationmark.triangle")
                .accessibilityLabel(delegate.model.isTrusted ? "Pane" : "Pane needs Accessibility access")
        }
    }
}

/// Settings live in an AppKit window: a menu-bar-only app can't reliably open a SwiftUI Settings scene.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = PaneModel()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.showSettings = { [weak self] in self?.showSettings() }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasOpenedSettings") || !model.isTrusted
            || CommandLine.arguments.contains("--settings") {
            showSettings()
        }
        defaults.set(true, forKey: "hasOpenedSettings")
    }

    // Opening Pane again while it's running (Finder, Spotlight, `open`) shows settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return false
    }

    func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "Pane"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.isReleasedWhenClosed = false
            window.setContentSize(controller.view.fittingSize)
            window.center()
            settingsWindow = window
        }
        model.refreshSystemStatus()
        // A hidden app (⌘H) keeps its windows off screen until it's unhidden.
        NSApplication.shared.unhide(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
        // Activate after the menu has finished closing; activating mid-dismissal is ignored.
        Task { @MainActor in NSApplication.shared.activate() }
    }
}

private struct PaneMenu: View {
    let model: PaneModel
    let showSettings: () -> Void

    var body: some View {
        if !model.isTrusted {
            Button("Allow Accessibility Access…") { model.requestAccessibility() }
        }
        if !model.shortcutErrors.isEmpty {
            Text("\(model.shortcutErrors.count) shortcut(s) need attention")
        }
        if let error = model.lastError {
            Text(error)
        }
        Button("Settings…", action: showSettings)
            .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit Pane") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
