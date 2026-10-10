import AppKit
import PaneCore

@MainActor
final class WindowManager {
    func perform(_ action: WindowAction, preferences: LayoutPreferences) throws {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        let application = Accessibility.application(frontmost.processIdentifier)
        guard let window = Accessibility.element(application, kAXFocusedWindowAttribute),
              let current = Accessibility.frame(window) else {
            // Checking permission costs a round trip, so only do it once something has failed.
            guard Accessibility.isTrusted else { throw WindowControlError.notTrusted }
            throw WindowControlError.message("This app has no accessible window to arrange.")
        }

        // NSScreen uses a bottom-left origin; Accessibility uses the primary display's top-left.
        let screens = NSScreen.screens
        guard let primary = screens.first else { return }
        let frames = screens.map {
            WindowGeometry.accessibilityFrame(from: $0.frame, primaryScreenTop: primary.frame.maxY)
        }
        guard let index = WindowGeometry.screenIndex(for: current, screens: frames) else { return }
        // Read visibleFrame on every action: Dock position, auto-hide and menu bar can change.
        let visible = WindowGeometry.accessibilityFrame(
            from: screens[index].visibleFrame, primaryScreenTop: primary.frame.maxY
        )
        let target = WindowGeometry.frame(for: action, current: current, visible: visible, preferences: preferences)
        guard Accessibility.isSettable(window, kAXPositionAttribute) else {
            throw WindowControlError.message("This window doesn’t support moving.")
        }
        // Fixed-size windows (Calculator, some settings windows) are still moved into place.
        let resizes = action != .center && Accessibility.isSettable(window, kAXSizeAttribute)
        if !resizes, action == .smaller || action == .bigger { return }
        if resizes {
            // Shrink before moving so a window can cross to a smaller desktop area.
            guard Accessibility.resize(window, to: target.size) == .success else {
                throw WindowControlError.message("This app couldn’t resize its window.")
            }
        }
        guard Accessibility.move(window, to: target.origin) == .success else {
            throw WindowControlError.message("This app couldn’t move its window.")
        }
        // macOS clamps a resize that would push the window off screen, so growing only fully
        // succeeds once the window is in place.
        if resizes, Accessibility.frame(window)?.size != target.size {
            _ = Accessibility.resize(window, to: target.size)
        }

        // Apps can enforce minimum sizes. Read back the accepted size before centering/clamping.
        guard let actual = Accessibility.frame(window) else { return }
        var corrected = actual
        if [.center, .almostMaximize, .smaller, .bigger].contains(action) {
            let center = CGPoint(x: target.midX, y: target.midY)
            corrected.origin = CGPoint(x: center.x - actual.width / 2, y: center.y - actual.height / 2)
        }
        if action != .center { corrected = WindowGeometry.clamped(corrected, to: visible) }
        if corrected.origin != actual.origin,
           Accessibility.move(window, to: corrected.origin) != .success {
            throw WindowControlError.message("This app couldn’t finish positioning its window.")
        }
    }
}
