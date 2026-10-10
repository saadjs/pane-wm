import Foundation
import Testing
@testable import PaneCore

struct ConfigurationTests {
    @Test func conflictsUseKeyCodeAndModifiersRatherThanDisplayLabel() {
        let shortcut = Shortcut(keyCode: 18, modifiers: Shortcut.control, keyLabel: "1")
        let sameKey = Shortcut(keyCode: 18, modifiers: Shortcut.control, keyLabel: "Different layout")
        var configuration = Configuration()
        let app = AppBinding(name: "Safari", bundleIdentifier: "com.apple.Safari", shortcut: shortcut)
        configuration.apps = [app]
        #expect(configuration.owner(of: sameKey) == "Safari")
        #expect(configuration.owner(of: sameKey, excludingApp: app.id) == nil)
        configuration.windowShortcuts[.center] = sameKey
        #expect(configuration.owner(of: shortcut, excludingApp: app.id) == "Center")
        #expect(configuration.owner(of: shortcut, excludingApp: app.id, excludingAction: .center) == nil)
    }

    @Test func defaultWindowShortcutsCoverEveryActionWithoutClashing() {
        var configuration = Configuration()
        configuration.assignDefaultWindowShortcuts()
        #expect(Set(configuration.windowShortcuts.keys) == Set(WindowAction.allCases))
        let shortcuts = Array(configuration.windowShortcuts.values)
        #expect(shortcuts.allSatisfy { $0.isValid })
        for shortcut in shortcuts {
            #expect(shortcuts.filter { $0.matches(shortcut) }.count == 1)
        }
    }

    @Test func defaultWindowShortcutsKeepExistingAssignments() {
        let leftDefault = Shortcut(keyCode: 123, modifiers: Shortcut.control | Shortcut.option, keyLabel: "←")
        let custom = Shortcut(keyCode: 0, modifiers: Shortcut.command | Shortcut.control, keyLabel: "A")
        var configuration = Configuration()
        configuration.apps = [AppBinding(name: "Safari", bundleIdentifier: "com.apple.Safari", shortcut: leftDefault)]
        configuration.windowShortcuts[.center] = custom
        configuration.assignDefaultWindowShortcuts()
        // The app keeps ⌃⌥←, so Left half stays unassigned rather than stealing it.
        #expect(configuration.windowShortcuts[.leftHalf] == nil)
        #expect(configuration.windowShortcuts[.center] == custom)
        #expect(configuration.windowShortcuts[.rightHalf] != nil)
    }

    @Test func shortcutsRequireASafeModifier() {
        #expect(!Shortcut(keyCode: 0, modifiers: 0, keyLabel: "A").isValid)
        #expect(!Shortcut(keyCode: 0, modifiers: Shortcut.shift, keyLabel: "A").isValid)
        #expect(Shortcut(keyCode: 0, modifiers: Shortcut.control, keyLabel: "A").isValid)
        #expect(!Shortcut(keyCode: 9999, modifiers: Shortcut.command, keyLabel: "A").isValid)
    }

    @Test func preferencesNormalizeInvalidValues() {
        let preferences = LayoutPreferences(gap: -.infinity, maximizeInset: 99999, resizeStep: -10).normalized
        #expect(preferences.gap == 12)
        #expect(preferences.maximizeInset == 160)
        #expect(preferences.resizeStep == 10)
    }

    @Test func settingsPersistAllBindingsAndLayout() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        var configuration = Configuration()
        configuration.apps = [.init(name: "Safari", bundleIdentifier: "com.apple.Safari", shortcut: .init(keyCode: 18, modifiers: Shortcut.control, keyLabel: "1"))]
        configuration.windowShortcuts[.leftHalf] = .init(keyCode: 123, modifiers: Shortcut.option, keyLabel: "←")
        configuration.layout = .init(gap: 8, maximizeInset: 24, resizeStep: 60, cycleSizes: false)
        try store.save(configuration)
        #expect(try store.load() == configuration)
    }

    @Test func settingsSavedBeforeAPreferenceExistedStillLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        let saved = #"{"apps":[],"layout":{"gap":8,"maximizeInset":24,"resizeStep":60},"version":1,"windowShortcuts":[]}"#
        try Data(saved.utf8).write(to: url)
        let layout = try SettingsStore(url: url).load().layout
        #expect(layout == LayoutPreferences(gap: 8, maximizeInset: 24, resizeStep: 60, cycleSizes: true))
    }

    @Test func corruptSettingsRemainUntouched() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        let original = Data("invalid json".utf8)
        try original.write(to: url)
        #expect(throws: (any Error).self) { try SettingsStore(url: url).load() }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func missingSettingsStartWithoutGlobalBindings() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("settings.json")
        let configuration = try SettingsStore(url: url).load()
        #expect(configuration.apps.isEmpty)
        #expect(configuration.windowShortcuts.isEmpty)
    }

    @Test func newerSettingsVersionsAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        var configuration = Configuration()
        configuration.version = 2
        try store.save(configuration)
        #expect(throws: SettingsStore.SettingsError.unsupportedVersion) { try store.load() }
    }
}
