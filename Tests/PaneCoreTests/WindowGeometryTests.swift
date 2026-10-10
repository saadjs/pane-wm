import Foundation
import CoreGraphics
import Testing
@testable import PaneCore

struct WindowGeometryTests {
    private let desktop = CGRect(x: -1440, y: 25, width: 1440, height: 835)
    private let current = CGRect(x: -1200, y: 100, width: 600, height: 400)

    @Test func maximizeUsesExactlyTheAvailableDesktop() {
        let result = frame(.maximize)
        #expect(result == desktop)
    }

    @Test func horizontalHalvesHaveExactInnerAndOuterGaps() {
        let left = frame(.leftHalf)
        let right = frame(.rightHalf)
        #expect(left.minX - desktop.minX == 12)
        #expect(desktop.maxX - right.maxX == 12)
        #expect(right.minX - left.maxX == 12)
        #expect(left.width == right.width)
        #expect(left.minY - desktop.minY == 12)
        #expect(desktop.maxY - left.maxY == 12)
    }

    @Test func verticalHalvesUseTopLeftAccessibilityCoordinates() {
        let top = frame(.topHalf)
        let bottom = frame(.bottomHalf)
        #expect(top.minY - desktop.minY == 12)
        #expect(desktop.maxY - bottom.maxY == 12)
        #expect(bottom.minY - top.maxY == 12)
        #expect(top.height == bottom.height)
    }

    @Test func zeroGapProducesFlushHalves() {
        let left = frame(.leftHalf, preferences: .init(gap: 0))
        let right = frame(.rightHalf, preferences: .init(gap: 0))
        #expect(left.union(right) == desktop)
        #expect(left.maxX == right.minX)
    }

    @Test func centerPreservesSizeEvenForOversizedWindows() {
        let large = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        let result = frame(.center, current: large)
        #expect(result.size == large.size)
        #expect(result.midX == desktop.midX)
        #expect(result.midY == desktop.midY)
    }

    @Test func almostMaximizeUsesItsOwnInset() {
        #expect(frame(.almostMaximize) == desktop.insetBy(dx: 32, dy: 32))
    }

    @Test(arguments: [WindowAction.bigger, .smaller])
    func resizeMaintainsCenterAwayFromEdges(_ action: WindowAction) {
        let result = frame(action)
        let step: CGFloat = action == .bigger ? 40 : -40
        #expect(result.width == current.width + step)
        #expect(result.height == current.height + step)
        #expect(result.midX == current.midX)
        #expect(result.midY == current.midY)
    }

    @Test func growthStopsAtTheDesktopEdges() {
        let result = frame(.bigger, current: desktop)
        #expect(result == desktop)
    }

    @Test func shrinkHasPositiveMinimumDimensions() {
        let small = CGRect(x: -1000, y: 100, width: 165, height: 105)
        let result = frame(.smaller, current: small)
        #expect(result.width == 160)
        #expect(result.height == 100)
    }

    @Test func offscreenResizeBringsWindowIntoTheDesktop() {
        let result = frame(.bigger, current: CGRect(x: 2000, y: 2000, width: 400, height: 300))
        #expect(desktop.contains(result))
    }

    @Test func coordinateConversionHandlesDisplaysAboveAndLeftOfPrimary() {
        let screen = CGRect(x: -1440, y: 900, width: 1440, height: 900)
        let result = WindowGeometry.accessibilityFrame(from: screen, primaryScreenTop: 900)
        #expect(result == CGRect(x: -1440, y: -900, width: 1440, height: 900))
    }

    @Test func screenSelectionUsesLargestIntersectionAndNearestScreenAsFallback() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: -300, width: 800, height: 1200)]
        #expect(WindowGeometry.screenIndex(for: CGRect(x: 950, y: 100, width: 400, height: 400), screens: screens) == 1)
        #expect(WindowGeometry.screenIndex(for: CGRect(x: 2200, y: 100, width: 100, height: 100), screens: screens) == 1)
        #expect(WindowGeometry.screenIndex(for: current, screens: []) == nil)
    }

    @Test func extremePreferencesNeverProduceNegativeSizes() {
        let visible = CGRect(x: 0, y: 0, width: 100, height: 70)
        let preferences = LayoutPreferences(gap: 80, maximizeInset: 160, resizeStep: 200)
        for action in WindowAction.allCases where action != .center {
            let result = WindowGeometry.frame(for: action, current: current, visible: visible, preferences: preferences)
            #expect(result.width > 0 && result.height > 0)
            #expect(visible.contains(result))
        }
    }

    private func frame(_ action: WindowAction, current override: CGRect? = nil, preferences: LayoutPreferences = .init()) -> CGRect {
        WindowGeometry.frame(for: action, current: override ?? current, visible: desktop, preferences: preferences)
    }
}
