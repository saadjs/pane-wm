import CoreGraphics

/// Geometry uses Accessibility's global coordinates: x rightwards, y downwards.
public enum WindowGeometry {
    public static func frame(
        for action: WindowAction, current: CGRect, visible: CGRect,
        preferences: LayoutPreferences
    ) -> CGRect {
        let preferences = preferences.normalized
        let tiles = tiles(for: action)
        if !tiles.isEmpty {
            let frames = tiles.map { frame(of: $0, in: visible, preferences: preferences) }
            // Pressing a half's shortcut again steps through its sizes.
            if preferences.cycleSizes, let index = closest(to: current, in: frames) {
                return frames[(index + 1) % frames.count]
            }
            return frames[0]
        }

        switch action {
        case .maximize:
            return visible
        case .center:
            return CGRect(
                x: visible.midX - current.width / 2, y: visible.midY - current.height / 2,
                width: current.width, height: current.height
            )
        case .almostMaximize:
            let inset = min(preferences.maximizeInset, max(0, (min(visible.width, visible.height) - 1) / 2))
            return visible.insetBy(dx: inset, dy: inset)
        case .smaller, .bigger:
            let delta = preferences.resizeStep * (action == .bigger ? 1 : -1)
            let width = min(visible.width, max(min(160, visible.width), current.width + delta))
            let height = min(visible.height, max(min(100, visible.height), current.height + delta))
            let result = CGRect(x: current.midX - width / 2, y: current.midY - height / 2, width: width, height: height)
            return clamped(result, to: visible)
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf,
             .topLeft, .topRight, .bottomLeft, .bottomRight,
             .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds:
            // Handled above: every tiling action has at least one tile.
            return fitted(current, in: visible)
        case .nextDisplay, .previousDisplay:
            // The destination comes from the display arrangement; see frame(moving:from:to:preferences:).
            return fitted(current, in: visible)
        }
    }

    /// The frame for a window sent from one display's desktop to another's.
    public static func frame(
        moving current: CGRect, from source: CGRect, to destination: CGRect,
        preferences: LayoutPreferences
    ) -> CGRect {
        // A tiled window stays tiled, with exact gaps on the new display.
        let preferences = preferences.normalized
        func layouts(_ visible: CGRect) -> [CGRect] {
            [visible, frame(for: .almostMaximize, current: current, visible: visible, preferences: preferences)]
                + WindowAction.allCases.flatMap(tiles).map { frame(of: $0, in: visible, preferences: preferences) }
        }
        if let index = closest(to: current, in: layouts(source)) { return layouts(destination)[index] }
        // Any other window keeps its size and its relative place: one against an edge stays there.
        let size = CGSize(width: min(current.width, destination.width), height: min(current.height, destination.height))
        func position(_ offset: CGFloat, _ sourceRoom: CGFloat, _ destinationRoom: CGFloat) -> CGFloat {
            (sourceRoom > 0 ? min(max(offset / sourceRoom, 0), 1) : 0.5) * destinationRoom
        }
        return CGRect(
            x: destination.minX + position(current.minX - source.minX, source.width - current.width, destination.width - size.width),
            y: destination.minY + position(current.minY - source.minY, source.height - current.height, destination.height - size.height),
            width: size.width, height: size.height
        )
    }

    /// The display `step` places after `index`, reading left to right then top to bottom and
    /// wrapping around. Nil when there is no other display.
    public static func screenIndex(after index: Int, step: Int, screens: [CGRect]) -> Int? {
        guard screens.count > 1, screens.indices.contains(index) else { return nil }
        let order = screens.indices.sorted {
            (screens[$0].minX, screens[$0].minY) < (screens[$1].minX, screens[$1].minY)
        }
        guard let position = order.firstIndex(of: index) else { return nil }
        return order[((position + step) % order.count + order.count) % order.count]
    }

    public static func fitted(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
        return clamped(CGRect(origin: frame.origin, size: size), to: visible)
    }

    public static func clamped(_ frame: CGRect, to visible: CGRect) -> CGRect {
        CGRect(
            x: min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width)),
            y: min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height)),
            width: frame.width, height: frame.height
        )
    }

    public static func accessibilityFrame(from appKitFrame: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: appKitFrame.minX, y: primaryScreenTop - appKitFrame.maxY,
               width: appKitFrame.width, height: appKitFrame.height)
    }

    public static func screenIndex(for window: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let areas = screens.map { screen -> CGFloat in
            let intersection = window.intersection(screen)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        if let index = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[index] > 0 {
            return index
        }
        // An off-screen window belongs to the nearest display.
        return screens.indices.min { distance(window, screens[$0]) < distance(window, screens[$1]) }
    }

    /// `count` of `parts` equal slices along one axis, starting at slice `first`.
    private struct Span {
        var first = 0, count = 1, parts = 1

        static func leading(_ count: Int, of parts: Int) -> Self { Self(first: 0, count: count, parts: parts) }
        static func trailing(_ count: Int, of parts: Int) -> Self { Self(first: parts - count, count: count, parts: parts) }

        func range(from origin: CGFloat, length: CGFloat, gap: CGFloat) -> (origin: CGFloat, length: CGFloat) {
            let slice = (length - gap * CGFloat(parts - 1)) / CGFloat(parts)
            let size = slice * CGFloat(count) + gap * CGFloat(count - 1)
            // Measure the last slices from the far edge so the outer gap is exact.
            let start = first + count == parts ? origin + length - size : origin + CGFloat(first) * (slice + gap)
            return (start, size)
        }
    }

    private struct Tile {
        var columns = Span(), rows = Span()
    }

    /// The tiles an action places a window in. Halves have several, which repeated presses cycle through.
    private static func tiles(for action: WindowAction) -> [Tile] {
        switch action {
        case .leftHalf: [1, 2].map { Tile(columns: .leading($0, of: $0 + 1)) } + [Tile(columns: .leading(1, of: 3))]
        case .rightHalf: [1, 2].map { Tile(columns: .trailing($0, of: $0 + 1)) } + [Tile(columns: .trailing(1, of: 3))]
        case .topHalf: [1, 2].map { Tile(rows: .leading($0, of: $0 + 1)) } + [Tile(rows: .leading(1, of: 3))]
        case .bottomHalf: [1, 2].map { Tile(rows: .trailing($0, of: $0 + 1)) } + [Tile(rows: .trailing(1, of: 3))]
        case .topLeft: [Tile(columns: .leading(1, of: 2), rows: .leading(1, of: 2))]
        case .topRight: [Tile(columns: .trailing(1, of: 2), rows: .leading(1, of: 2))]
        case .bottomLeft: [Tile(columns: .leading(1, of: 2), rows: .trailing(1, of: 2))]
        case .bottomRight: [Tile(columns: .trailing(1, of: 2), rows: .trailing(1, of: 2))]
        case .leftThird: [Tile(columns: .leading(1, of: 3))]
        case .centerThird: [Tile(columns: Span(first: 1, count: 1, parts: 3))]
        case .rightThird: [Tile(columns: .trailing(1, of: 3))]
        case .leftTwoThirds: [Tile(columns: .leading(2, of: 3))]
        case .rightTwoThirds: [Tile(columns: .trailing(2, of: 3))]
        case .maximize, .center, .almostMaximize, .smaller, .bigger, .nextDisplay, .previousDisplay: []
        }
    }

    private static func frame(of tile: Tile, in visible: CGRect, preferences: LayoutPreferences) -> CGRect {
        // Keep room for three slices and four gaps on the smallest desktops.
        let gap = min(preferences.gap, max(0, (min(visible.width, visible.height) - 4) / 5))
        let tiled = visible.insetBy(dx: gap, dy: gap)
        let x = tile.columns.range(from: tiled.minX, length: tiled.width, gap: gap)
        let y = tile.rows.range(from: tiled.minY, length: tiled.height, gap: gap)
        return CGRect(x: x.origin, y: y.origin, width: x.length, height: y.length)
    }

    /// The frame `window` sits in. Apps that resize in steps (terminals) land near a tile rather
    /// than on it, hence the tolerance.
    private static func closest(to window: CGRect, in frames: [CGRect]) -> Int? {
        let deviations = frames.map { deviation(window, $0) }
        guard let index = deviations.indices.min(by: { deviations[$0] < deviations[$1] }), deviations[index] <= 20 else {
            return nil
        }
        return index
    }

    private static func deviation(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.maxX - b.maxX), abs(a.maxY - b.maxY))
    }

    private static func distance(_ window: CGRect, _ screen: CGRect) -> CGFloat {
        let x = max(screen.minX - window.midX, 0, window.midX - screen.maxX)
        let y = max(screen.minY - window.midY, 0, window.midY - screen.maxY)
        return x * x + y * y
    }
}
