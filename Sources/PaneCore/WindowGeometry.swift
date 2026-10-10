import CoreGraphics

/// Geometry uses Accessibility's global coordinates: x rightwards, y downwards.
public enum WindowGeometry {
    public static func frame(
        for action: WindowAction, current: CGRect, visible: CGRect,
        preferences: LayoutPreferences
    ) -> CGRect {
        let preferences = preferences.normalized
        let gap = min(preferences.gap, max(0, (min(visible.width, visible.height) - 4) / 3))
        let tiled = visible.insetBy(dx: gap, dy: gap)
        let halfWidth = (tiled.width - gap) / 2
        let halfHeight = (tiled.height - gap) / 2

        switch action {
        case .maximize:
            return visible
        case .leftHalf:
            return CGRect(x: tiled.minX, y: tiled.minY, width: halfWidth, height: tiled.height)
        case .rightHalf:
            return CGRect(x: tiled.maxX - halfWidth, y: tiled.minY, width: halfWidth, height: tiled.height)
        case .topHalf:
            return CGRect(x: tiled.minX, y: tiled.minY, width: tiled.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: tiled.minX, y: tiled.maxY - halfHeight, width: tiled.width, height: halfHeight)
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
        // A tiled window stays tiled, with exact gaps on the new display. Apps that resize in
        // steps (terminals) land near the tile rather than on it, hence the tolerance.
        let tiles: [WindowAction] = [.maximize, .almostMaximize, .leftHalf, .rightHalf, .topHalf, .bottomHalf]
        let deviations = tiles.map {
            deviation(current, frame(for: $0, current: current, visible: source, preferences: preferences))
        }
        if let index = deviations.indices.min(by: { deviations[$0] < deviations[$1] }), deviations[index] <= 20 {
            return frame(for: tiles[index], current: current, visible: destination, preferences: preferences)
        }
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

    private static func deviation(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.maxX - b.maxX), abs(a.maxY - b.maxY))
    }

    private static func distance(_ window: CGRect, _ screen: CGRect) -> CGFloat {
        let x = max(screen.minX - window.midX, 0, window.midX - screen.maxX)
        let y = max(screen.minY - window.midY, 0, window.midY - screen.maxY)
        return x * x + y * y
    }
}
