import Foundation

public enum WindowAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case maximize, leftHalf, rightHalf, topHalf, bottomHalf
    case center, almostMaximize, smaller, bigger
    case nextDisplay, previousDisplay

    public var id: Self { self }

    /// The direction to move through the displays, for actions that send a window to another one.
    public var displayStep: Int? {
        switch self {
        case .nextDisplay: 1
        case .previousDisplay: -1
        default: nil
        }
    }

    public var title: String {
        switch self {
        case .maximize: "Maximize"
        case .leftHalf: "Left half"
        case .rightHalf: "Right half"
        case .topHalf: "Top half"
        case .bottomHalf: "Bottom half"
        case .center: "Center"
        case .almostMaximize: "Almost maximize"
        case .smaller: "Make smaller"
        case .bigger: "Make bigger"
        case .nextDisplay: "Next display"
        case .previousDisplay: "Previous display"
        }
    }

    public var symbol: String {
        switch self {
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .center: "scope"
        case .almostMaximize: "rectangle.inset.filled"
        case .smaller: "arrow.down.right.and.arrow.up.left"
        case .bigger: "arrow.up.left.and.arrow.down.right"
        case .nextDisplay: "arrow.right.square"
        case .previousDisplay: "arrow.left.square"
        }
    }
}

public struct Shortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var keyLabel: String

    // HIToolbox modifier bits. Keeping these values here avoids a UI dependency.
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12
    public static let supportedModifiers = command | shift | option | control

    public init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    public var isValid: Bool {
        keyCode <= 127 && modifiers & (Self.command | Self.option | Self.control) != 0
            && modifiers & ~Self.supportedModifiers == 0
    }

    public func matches(_ other: Self) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    /// Rectangle-style defaults: Control + Option with arrows, Return, C, minus and equals, plus
    /// Command with the horizontal arrows to change display.
    public static let windowDefaults: [(WindowAction, Shortcut)] = {
        let base = control | option
        return [
            (.leftHalf, Shortcut(keyCode: 123, modifiers: base, keyLabel: "←")),
            (.rightHalf, Shortcut(keyCode: 124, modifiers: base, keyLabel: "→")),
            (.topHalf, Shortcut(keyCode: 126, modifiers: base, keyLabel: "↑")),
            (.bottomHalf, Shortcut(keyCode: 125, modifiers: base, keyLabel: "↓")),
            (.maximize, Shortcut(keyCode: 36, modifiers: base, keyLabel: "↩")),
            (.almostMaximize, Shortcut(keyCode: 36, modifiers: base | shift, keyLabel: "↩")),
            (.center, Shortcut(keyCode: 8, modifiers: base, keyLabel: "C")),
            (.smaller, Shortcut(keyCode: 27, modifiers: base, keyLabel: "-")),
            (.bigger, Shortcut(keyCode: 24, modifiers: base, keyLabel: "=")),
            (.nextDisplay, Shortcut(keyCode: 124, modifiers: base | command, keyLabel: "→")),
            (.previousDisplay, Shortcut(keyCode: 123, modifiers: base | command, keyLabel: "←")),
        ]
    }()

    public var label: String {
        var result = ""
        if modifiers & Self.control != 0 { result += "⌃" }
        if modifiers & Self.option != 0 { result += "⌥" }
        if modifiers & Self.shift != 0 { result += "⇧" }
        if modifiers & Self.command != 0 { result += "⌘" }
        return result + keyLabel
    }
}

public struct AppBinding: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var bundleIdentifier: String
    public var shortcut: Shortcut?

    public init(id: UUID = UUID(), name: String, bundleIdentifier: String, shortcut: Shortcut? = nil) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.shortcut = shortcut
    }
}

public struct LayoutPreferences: Codable, Equatable, Sendable {
    public var gap: Double = 12
    public var maximizeInset: Double = 32
    public var resizeStep: Double = 40

    public init(gap: Double = 12, maximizeInset: Double = 32, resizeStep: Double = 40) {
        self.gap = gap
        self.maximizeInset = maximizeInset
        self.resizeStep = resizeStep
    }

    public var normalized: Self {
        Self(
            gap: gap.isFinite ? min(max(gap, 0), 80) : 12,
            maximizeInset: maximizeInset.isFinite ? min(max(maximizeInset, 0), 160) : 32,
            resizeStep: resizeStep.isFinite ? min(max(resizeStep, 10), 200) : 40
        )
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public var version = 1
    public var apps: [AppBinding] = []
    public var windowShortcuts: [WindowAction: Shortcut] = [:]
    public var layout = LayoutPreferences()

    public init() {}

    /// Fills unassigned window actions with their defaults, skipping shortcuts already used elsewhere.
    public mutating func assignDefaultWindowShortcuts() {
        for (action, shortcut) in Shortcut.windowDefaults
        where windowShortcuts[action] == nil && owner(of: shortcut) == nil {
            windowShortcuts[action] = shortcut
        }
    }

    public func owner(of shortcut: Shortcut, excludingApp: UUID? = nil, excludingAction: WindowAction? = nil) -> String? {
        if let app = apps.first(where: { $0.id != excludingApp && $0.shortcut?.matches(shortcut) == true }) {
            return app.name
        }
        return WindowAction.allCases.first {
            $0 != excludingAction && windowShortcuts[$0]?.matches(shortcut) == true
        }?.title
    }
}
