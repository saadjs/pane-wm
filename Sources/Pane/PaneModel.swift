import AppKit
import Observation
import os
import PaneCore
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
@Observable
final class PaneModel {
    var configuration: Configuration {
        didSet {
            guard settingsLoadError == nil else { return }
            do { try store.save(configuration) }
            catch { alert = "Couldn’t save settings: \(error.localizedDescription)" }
            // Dragging a layout slider shouldn't re-register every hotkey on each tick.
            if configuration.apps != oldValue.apps || configuration.windowShortcuts != oldValue.windowShortcuts {
                updateHotKeys()
            }
        }
    }
    var isTrusted = Accessibility.isTrusted
    var shortcutErrors: [ShortcutTarget: String] = [:]
    var alert: String?
    var lastError: String?
    var settingsLoadError: String?
    var loginStatus = SMAppService.mainApp.status
    var isRecordingShortcut = false {
        didSet { updateHotKeys() }
    }

    private static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "sh.saad.pane"
    private static let log = Logger(subsystem: bundleIdentifier, category: "actions")
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let hotKeys = HotKeyManager()
    @ObservationIgnored private let windows = WindowManager()
    @ObservationIgnored private let applications = ApplicationManager()
    @ObservationIgnored private var launching: Set<UUID> = []
    @ObservationIgnored var showSettings: (() -> Void)?

    init() {
        let support = URL.applicationSupportDirectory.appendingPathComponent(Self.bundleIdentifier, isDirectory: true)
        store = SettingsStore(url: support.appendingPathComponent("settings.json"))
        do { configuration = try store.load() }
        catch {
            configuration = Configuration()
            settingsLoadError = "Couldn’t read settings: \(error.localizedDescription) Your existing file has been preserved."
        }
        hotKeys.onTrigger = { [weak self] target in self?.perform(target) }
        updateHotKeys()
        // macOS posts this whenever any app's Accessibility permission changes, so no polling is needed.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityChanged() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshSystemStatus()
                self?.retryShortcuts()
            }
        }
    }

    func refreshSystemStatus() {
        let trusted = Accessibility.isTrusted
        if trusted != isTrusted { isTrusted = trusted }
        let login = SMAppService.mainApp.status
        if login != loginStatus { loginStatus = login }
    }

    private func accessibilityChanged() {
        Task {
            // The notification can arrive just before the new state is readable.
            try? await Task.sleep(for: .milliseconds(500))
            refreshSystemStatus()
            if !isTrusted, await Accessibility.isTrustedInFreshProcess() { relaunch() }
        }
    }

    /// Replaces this process with a new one that sees the current permission.
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--settings"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }

    /// Adds Pane to the Accessibility list (first time, macOS also prompts) and opens that list.
    func requestAccessibility() {
        refreshSystemStatus()
        guard !isTrusted else { return }
        Accessibility.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { alert = "Couldn’t update launch at login: \(error.localizedDescription)" }
        refreshSystemStatus()
    }

    func assignDefaultWindowShortcuts() {
        var updated = configuration
        updated.assignDefaultWindowShortcuts()
        configuration = updated
    }

    func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.prompt = "Add Application"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
                alert = "This application has no bundle identifier."
                continue
            }
            guard identifier != Self.bundleIdentifier else {
                alert = "Choose an application other than Pane."
                continue
            }
            guard !configuration.apps.contains(where: { $0.bundleIdentifier == identifier }) else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            configuration.apps.append(AppBinding(name: name, bundleIdentifier: identifier))
        }
    }

    func shortcut(for target: ShortcutTarget) -> Shortcut? {
        switch target {
        case .app(let id): configuration.apps.first { $0.id == id }?.shortcut
        case .window(let action): configuration.windowShortcuts[action]
        }
    }

    @discardableResult
    func assign(_ shortcut: Shortcut?, to target: ShortcutTarget) -> Bool {
        if let shortcut, let error = assignmentError(for: shortcut, to: target) {
            alert = error
            return false
        }
        switch target {
        case .app(let id):
            if let index = configuration.apps.firstIndex(where: { $0.id == id }) {
                configuration.apps[index].shortcut = shortcut
            }
        case .window(let action): configuration.windowShortcuts[action] = shortcut
        }
        return true
    }

    func assignmentError(for shortcut: Shortcut, to target: ShortcutTarget) -> String? {
        guard shortcut.isValid else { return "Include Control, Option, or Command in your shortcut." }
        let owner: String?
        switch target {
        case .app(let id): owner = configuration.owner(of: shortcut, excludingApp: id)
        case .window(let action): owner = configuration.owner(of: shortcut, excludingAction: action)
        }
        if let owner {
            return "\(shortcut.label) is already assigned to \(owner). Choose another shortcut or clear that assignment first."
        }
        return nil
    }

    func revealSettings() {
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }

    /// Re-registers so conflicts that came or went (another app quit, a macOS shortcut toggled) show up.
    func retryShortcuts() { updateHotKeys() }

    private func updateHotKeys() {
        guard !isRecordingShortcut, settingsLoadError == nil else {
            hotKeys.unregister()
            return
        }
        var bindings: [(ShortcutTarget, Shortcut)] = configuration.apps.compactMap { app in
            app.shortcut.map { (.app(app.id), $0) }
        }
        bindings += WindowAction.allCases.compactMap { action in
            configuration.windowShortcuts[action].map { (.window(action), $0) }
        }
        shortcutErrors = hotKeys.register(bindings)
    }

    private func perform(_ target: ShortcutTarget) {
        let clock = ContinuousClock()
        let start = clock.now
        defer { Self.log.debug("perform took \(String(describing: clock.now - start), privacy: .public)") }
        switch target {
        case .window(let action):
            do {
                try windows.perform(action, preferences: configuration.layout)
                lastError = nil
            } catch WindowControlError.notTrusted {
                isTrusted = false
                showSettings?()
            } catch { report(error) }
        case .app(let id):
            guard let binding = configuration.apps.first(where: { $0.id == id }), !launching.contains(id) else { return }
            launching.insert(id)
            Task {
                defer { launching.remove(id) }
                do {
                    try await applications.activate(binding)
                    lastError = nil
                } catch { report(error) }
            }
        }
    }

    private func report(_ error: any Error) {
        lastError = error.localizedDescription
        Self.log.error("\(error.localizedDescription, privacy: .public)")
        NSSound.beep()
    }
}
