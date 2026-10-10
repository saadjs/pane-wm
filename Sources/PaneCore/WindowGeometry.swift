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
        }
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

    private static func distance(_ window: CGRect, _ screen: CGRect) -> CGFloat {
        let x = max(screen.minX - window.midX, 0, window.midX - screen.maxX)
        let y = max(screen.minY - window.midY, 0, window.midY - screen.maxY)
        return x * x + y * y
    }
}
