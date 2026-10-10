import Foundation

public enum WindowAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case maximize, leftHalf, rightHalf, topHalf, bottomHalf
    case center, almostMaximize, smaller, bigger
    case nextDisplay, previousDisplay
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds

    public var id: Self { self }

    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case halves = "Halves", quarters = "Quarters", thirds = "Thirds", size = "Size", displays = "Displays"

        public var id: Self { self }
        public var actions: [WindowAction] { WindowAction.allCases.filter { $0.group == self } }
    }

    public var group: Group {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: .halves
        case .topLeft, .topRight, .bottomLeft, .bottomRight: .quarters
        case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds: .thirds
        case .maximize, .almostMaximize, .center, .smaller, .bigger: .size
        case .nextDisplay, .previousDisplay: .displays
        }
    }

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
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .leftThird: "Left third"
        case .centerThird: "Center third"
        case .rightThird: "Right third"
        case .leftTwoThirds: "Left two thirds"
        case .rightTwoThirds: "Right two thirds"
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
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .leftThird: "rectangle.leftthird.inset.filled"
        case .centerThird: "rectangle.center.inset.filled"
        case .rightThird: "rectangle.rightthird.inset.filled"
        case .leftTwoThirds: "rectangle.lefthalf.inset.filled"
        case .rightTwoThirds: "rectangle.righthalf.inset.filled"
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

    /// Rectangle-style defaults: Control + Option with arrows, Return, C, minus and equals, U I J K
    /// for quarters and D F G E T for thirds, plus Command with the horizontal arrows to change display.
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
            (.topLeft, Shortcut(keyCode: 32, modifiers: base, keyLabel: "U")),
            (.topRight, Shortcut(keyCode: 34, modifiers: base, keyLabel: "I")),
            (.bottomLeft, Shortcut(keyCode: 38, modifiers: base, keyLabel: "J")),
            (.bottomRight, Shortcut(keyCode: 40, modifiers: base, keyLabel: "K")),
            (.leftThird, Shortcut(keyCode: 2, modifiers: base, keyLabel: "D")),
            (.centerThird, Shortcut(keyCode: 3, modifiers: base, keyLabel: "F")),
            (.rightThird, Shortcut(keyCode: 5, modifiers: base, keyLabel: "G")),
            (.leftTwoThirds, Shortcut(keyCode: 14, modifiers: base, keyLabel: "E")),
            (.rightTwoThirds, Shortcut(keyCode: 17, modifiers: base, keyLabel: "T")),
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
    public var gap: Double
    public var maximizeInset: Double
    public var resizeStep: Double
    /// Pressing a half's shortcut again steps through two thirds and one third.
    public var cycleSizes: Bool

    public init(gap: Double = 12, maximizeInset: Double = 32, resizeStep: Double = 40, cycleSizes: Bool = true) {
        self.gap = gap
        self.maximizeInset = maximizeInset
        self.resizeStep = resizeStep
        self.cycleSizes = cycleSizes
    }

    // Settings saved before a preference existed don't have its key.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        gap = try container.decodeIfPresent(Double.self, forKey: .gap) ?? defaults.gap
        maximizeInset = try container.decodeIfPresent(Double.self, forKey: .maximizeInset) ?? defaults.maximizeInset
        resizeStep = try container.decodeIfPresent(Double.self, forKey: .resizeStep) ?? defaults.resizeStep
        cycleSizes = try container.decodeIfPresent(Bool.self, forKey: .cycleSizes) ?? defaults.cycleSizes
    }

    public var normalized: Self {
        Self(
            gap: gap.isFinite ? min(max(gap, 0), 80) : 12,
            maximizeInset: maximizeInset.isFinite ? min(max(maximizeInset, 0), 160) : 32,
            resizeStep: resizeStep.isFinite ? min(max(resizeStep, 10), 200) : 40,
            cycleSizes: cycleSizes
        )
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public var version = 1
    public var apps: [AppBinding] = []
    public var windowShortcuts: [WindowAction: Shortcut] = [:]
    public var layout = LayoutPreferences()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, apps, windowShortcuts, layout
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        apps = try container.decodeIfPresent([AppBinding].self, forKey: .apps) ?? []
        layout = try container.decodeIfPresent(LayoutPreferences.self, forKey: .layout) ?? LayoutPreferences()
        for (name, shortcut) in try container.decodeIfPresent([String: Shortcut].self, forKey: .windowShortcuts) ?? [:] {
            guard let action = WindowAction(rawValue: name) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .windowShortcuts, in: container, debugDescription: "“\(name)” is not a window action."
                )
            }
            windowShortcuts[action] = shortcut
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(apps, forKey: .apps)
        try container.encode(layout, forKey: .layout)
        let named = Dictionary(uniqueKeysWithValues: windowShortcuts.map { ($0.key.rawValue, $0.value) })
        try container.encode(named, forKey: .windowShortcuts)
    }

    /// Fills unassigned window actions with their defaults, skipping shortcuts already used elsewhere.
    public mutating func assignDefaultWindowShortcuts() {
        for (action, shortcut) in Shortcut.windowDefaults
        where windowShortcuts[action] == nil && owner(of: shortcut) == nil {
            windowShortcuts[action] = shortcut
        }
    }

    public var duplicateApp: String? {
        for (index, app) in apps.enumerated() {
            for earlier in apps[..<index] {
                if earlier.bundleIdentifier == app.bundleIdentifier { return "\(app.name) is listed more than once." }
                if earlier.id == app.id { return "\(earlier.name) and \(app.name) have the same id." }
            }
        }
        return nil
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
