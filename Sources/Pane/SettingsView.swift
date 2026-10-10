import AppKit
import PaneCore
import ServiceManagement
import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case apps = "Apps"
    case windows = "Windows"
    case general = "General"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .apps: "app.badge"
        case .windows: "rectangle.split.2x1"
        case .general: "gearshape"
        }
    }
}

struct SettingsView: View {
    @Bindable var model: PaneModel
    @State private var selection: SettingsPage? = .apps

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selection) { page in
                Label(page.rawValue, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(160)
        } detail: {
            Form {
                if let error = model.settingsLoadError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                        Button("Reveal Settings File") { model.revealSettings() }
                    }
                }
                if !model.isTrusted { accessibilitySection }
                Group {
                    switch selection ?? .apps {
                    case .apps: appSettings
                    case .windows: windowSettings
                    case .general: generalSettings
                    }
                }
                .disabled(model.settingsLoadError != nil)
            }
            .formStyle(.grouped)
        }
        .frame(width: 640, height: 500)
        .alert("Pane", isPresented: Binding(
            get: { model.alert != nil },
            set: { if !$0 { model.alert = nil } }
        )) {
            Button("OK", role: .cancel) { model.alert = nil }
        } message: {
            Text(model.alert ?? "")
        }
    }

    private var accessibilitySection: some View {
        Section {
            LabeledContent {
                Button("Open Settings…") { model.requestAccessibility() }
            } label: {
                Label("Pane needs Accessibility access", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                Text("Turn on Pane in the list that opens.")
            }
        }
    }

    @ViewBuilder
    private var appSettings: some View {
        if model.configuration.apps.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No Apps", systemImage: "command.square")
                } description: {
                    Text("Add an app to open it with a shortcut.")
                } actions: {
                    Button("Add App…") { model.addApplication() }
                }
            }
        } else {
            Section {
                ForEach(model.configuration.apps) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(nsImage: icon(for: app))
                                .resizable().frame(width: 26, height: 26)
                                .accessibilityHidden(true)
                            Text(app.name).lineLimit(1)
                            Spacer(minLength: 8)
                            ShortcutControl(model: model, target: .app(app.id), name: app.name)
                            Button {
                                model.configuration.apps.removeAll { $0.id == app.id }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("Remove \(app.name)")
                                .accessibilityLabel("Remove \(app.name)")
                        }
                        shortcutError(.app(app.id))
                    }
                }
            } footer: {
                HStack {
                    Spacer()
                    Button("Add App…") { model.addApplication() }
                }
            }
        }
    }

    private var windowSettings: some View {
        ForEach(WindowAction.Group.allCases) { group in
            Section {
                ForEach(group.actions) { action in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: action.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            Text(action.title)
                            Spacer(minLength: 8)
                            ShortcutControl(model: model, target: .window(action), name: action.title)
                        }
                        shortcutError(.window(action))
                    }
                }
            } header: {
                Text(group.rawValue)
            } footer: {
                if group == WindowAction.Group.allCases.last,
                   model.configuration.windowShortcuts.count < WindowAction.allCases.count {
                    HStack {
                        Spacer()
                        Button("Use Default Shortcuts") { model.assignDefaultWindowShortcuts() }
                            .help("Fill unassigned actions with ⌃⌥ shortcuts")
                    }
                }
            }
        }
    }

    private var generalSettings: some View {
        Group {
            Section {
                valueSlider("Gap", value: $model.configuration.layout.gap, range: 0...80, step: 1)
                valueSlider("Almost maximize inset", value: $model.configuration.layout.maximizeInset, range: 0...160, step: 4)
                valueSlider("Resize step", value: $model.configuration.layout.resizeStep, range: 10...200, step: 10)
                Toggle(isOn: $model.configuration.layout.cycleSizes) {
                    Text("Cycle sizes")
                    Text("Pressing a half’s shortcut again steps through two thirds and one third.")
                }
            }
            Section {
                Toggle("Launch at login", isOn: launchAtLogin)
                if model.loginStatus == .requiresApproval {
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Section {
                LabeledContent("Settings file") {
                    Text((model.settingsURL.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(model.settingsURL.path)
                }
            } footer: {
                HStack {
                    Text("Edits to this file apply right away.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reveal") { model.revealSettings() }
                    Button("Import…") { model.importSettings() }
                    Button("Export…") { model.exportSettings() }
                }
            }
        }
    }

    private var launchAtLogin: Binding<Bool> {
        let model = model
        return Binding(
            get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
            set: { model.setLaunchAtLogin($0) }
        )
    }

    @ViewBuilder
    private func shortcutError(_ target: ShortcutTarget) -> some View {
        if let error = model.shortcutErrors[target] {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private func icon(for app: AppBinding) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        LabeledContent(title) {
            Slider(value: value, in: range, step: step)
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value.wrappedValue)) points")
            Text("\(Int(value.wrappedValue)) pt").monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
