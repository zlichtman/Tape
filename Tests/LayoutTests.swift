import XCTest
import CoreGraphics
@testable import TapeEngine

final class LayoutTests: XCTestCase {
    private let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 825))
    private let options = LayoutOptions(gap: 8, edgeGap: 8)
    private func strip(_ count: Int, width: ColumnWidth = .fraction(0.5)) -> Strip {
        var result = Strip()
        for _ in 0..<count { result.insert(WindowID(), foreground: true, width: width) }
        // These geometry fixtures exercise explicitly chosen widths.
        for index in result.columns.indices { result.columns[index].automaticWidth = false }
        result.focusedWindow = result.columns.first?.windows.first
        return result
    }

    func testEmptyStripHasNoFrames() {
        XCTAssertTrue(Layout.frames(for: Strip(), screen: screen, options: options).isEmpty)
    }
    func testAutomaticLoneWindowFillsScreenAndTabNotificationsCannotHalveIt() {
        var model = Strip()
        let id = WindowID()
        model.insert(id, foreground: true)
        XCTAssertEqual(Layout.frames(for: model, screen: screen, options: options)[id]?.width, 1424)
        model.insert(id, foreground: true) // Same native window, another app tab.
        XCTAssertEqual(Layout.frames(for: model, screen: screen, options: options)[id]?.width, 1424)
        let other = WindowID()
        model.insert(other, foreground: true)
        XCTAssertEqual(Layout.frames(for: model, screen: screen, options: options)[id]?.width, 712)
        model.remove(other)
        XCTAssertEqual(Layout.frames(for: model, screen: screen, options: options)[id]?.width, 1424)
        model.perform(.setWidth(0.5))
        XCTAssertEqual(Layout.frames(for: model, screen: screen, options: options)[id]?.width, 712)
    }
    func testFramesRespectMenuBarDockAndEdgeGaps() {
        let model = strip(1)
        let frame = Layout.frames(for: model, screen: screen, options: options).values.first!
        XCTAssertEqual(frame.minX, 8)
        XCTAssertEqual(frame.minY, 33)
        XCTAssertEqual(frame.maxY, 842)
        XCTAssertEqual(frame.width, 712)
    }
    func testFullWidthExcludesBothEdgeGaps() {
        let frame = Layout.frames(for: strip(1, width: .fraction(1)), screen: screen, options: options).values.first!
        XCTAssertEqual(frame.width, 1424)
        XCTAssertEqual(frame.maxX, 1432)
    }
    func testAppMinimumWidthRetainsPresetAndPushesNextColumn() {
        var model = strip(2)
        model.columns[0].minimumWidth = 900
        let rects = Layout.columnRects(for: model, screen: screen, options: options)
        XCTAssertEqual(rects[0].width, 900)
        XCTAssertEqual(rects[1].minX, 916)
        XCTAssertEqual(model.columns[0].width, .fraction(0.5))
    }
    func testLogicalColumnsNeverOverlap() {
        let rects = Layout.columnRects(for: strip(12), screen: screen, options: options)
        for (left, right) in zip(rects, rects.dropFirst()) { XCTAssertEqual(right.minX - left.maxX, 8) }
    }
    func testZeroGapsAreSupported() {
        let rects = Layout.columnRects(for: strip(2), screen: screen, options: LayoutOptions(gap: 0, edgeGap: 0))
        XCTAssertEqual(rects[0].minX, 0)
        XCTAssertEqual(rects[0].maxX, rects[1].minX)
        XCTAssertEqual(rects[1].maxX, 1440)
    }
    func testViewportOffsetDoesNotChangeColumnWidth() {
        var model = strip(3)
        let before = Layout.columnRects(for: model, screen: screen, options: options)
        model.scrollOffset = 350
        let after = Layout.columnRects(for: model, screen: screen, options: options)
        for (old, new) in zip(before, after) {
            XCTAssertEqual(old.width, new.width)
            XCTAssertEqual(new.minX, old.minX - 350)
        }
    }
    func testFocusOnlyScrollsAsFarAsNeeded() {
        var model = strip(3)
        model.perform(.focus(.right))
        XCTAssertEqual(Layout.revealedOffset(for: model, screen: screen, options: options), 8)
        model.scrollOffset = 8
        XCTAssertEqual(Layout.revealedOffset(for: model, screen: screen, options: options), 8)
        model.perform(.focus(.last))
        XCTAssertEqual(Layout.revealedOffset(for: model, screen: screen, options: options), 728)
    }
    func testFocusLeftRevealsFirstColumn() {
        var model = strip(3)
        model.scrollOffset = 700
        XCTAssertEqual(Layout.revealedOffset(for: model, screen: screen, options: options), 0)
    }
    func testAlwaysCenterCanAddLeadingSpace() {
        let value = Layout.revealedOffset(for: strip(1), screen: screen, options: LayoutOptions(centering: .always))
        XCTAssertEqual(value, -356)
    }
    func testOverflowCenterOnlyAppliesToOverflowingStrip() {
        let options = LayoutOptions(centering: .overflow)
        XCTAssertEqual(Layout.revealedOffset(for: strip(1), screen: screen, options: options), 0)
        XCTAssertEqual(Layout.revealedOffset(for: strip(3), screen: screen, options: options), -356)
    }
    func testExplicitCenterWorksWithoutOverflow() {
        XCTAssertEqual(Layout.revealedOffset(for: strip(1), screen: screen, options: options, forceCenter: true), -356)
    }
    func testWidthsCannotExceedViewportOrCollapse() {
        XCTAssertEqual(ColumnWidth.fraction(2).resolve(in: 1424), 1424)
        XCTAssertEqual(ColumnWidth.points(-100).resolve(in: 1424), 160)
        XCTAssertEqual(ColumnWidth.fraction(.nan).resolve(in: 1424), 712)
        XCTAssertEqual(ColumnWidth.points(600).resolve(in: 100), 100)
    }
    func testGapsCannotInvertContentRect() {
        let content = Layout.contentRect(screen: screen, options: LayoutOptions(gap: -1, edgeGap: 10000))
        XCTAssertGreaterThan(content.width, 0)
        XCTAssertGreaterThan(content.height, 0)
    }
    func testLeftParkingKeepsSixPointsVisible() {
        let result = Layout.parked(CGRect(x: -3000, y: 33, width: 712, height: 809), on: screen)
        XCTAssertEqual(result.maxX, 6)
        XCTAssertGreaterThan(result.intersection(screen.frame).width, 0)
    }
    func testRightParkingKeepsSixPointsVisible() {
        let result = Layout.parked(CGRect(x: 3000, y: 33, width: 712, height: 809), on: screen)
        XCTAssertEqual(result.minX, 1434)
        XCTAssertEqual(result.intersection(screen.frame).width, 6)
    }
    func testSharedRightEdgeNeverEntersNeighbor() {
        var screen = screen
        let neighbor = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        screen.neighbors = [neighbor]
        let result = Layout.parked(CGRect(x: 3000, y: 33, width: 712, height: 809), on: screen)
        XCTAssertFalse(result.intersects(neighbor))
        XCTAssertEqual(result.maxX, screen.frame.maxX)
    }
    func testSharedLeftEdgeNeverEntersNeighbor() {
        var screen = screen
        let neighbor = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        screen.neighbors = [neighbor]
        let result = Layout.parked(CGRect(x: -3000, y: 33, width: 712, height: 809), on: screen)
        XCTAssertFalse(result.intersects(neighbor))
        XCTAssertEqual(result.minX, 0)
    }
    func testStackedDisplayParkingStaysVerticallyContained() {
        var screen = screen
        screen.neighbors = [CGRect(x: 0, y: -900, width: 1440, height: 900), CGRect(x: 0, y: 900, width: 1440, height: 900)]
        for y: CGFloat in [-2000, 3000] {
            let result = Layout.parked(CGRect(x: -2000, y: y, width: 600, height: 2000), on: screen)
            XCTAssertGreaterThanOrEqual(result.minY, screen.visibleFrame.minY)
            XCTAssertLessThanOrEqual(result.maxY, screen.visibleFrame.maxY)
            XCTAssertFalse(screen.neighbors.contains { $0.intersects(result) })
        }
    }
    func testSecondaryCoordinateSystemSupportsNegativeOrigin() {
        let screen = ScreenGeometry(frame: CGRect(x: -1600, y: -700, width: 1600, height: 900),
                                    visibleFrame: CGRect(x: -1600, y: -675, width: 1600, height: 825))
        let frame = Layout.frames(for: strip(1), screen: screen, options: options).values.first!
        XCTAssertEqual(frame.minX, -1592)
        XCTAssertEqual(frame.minY, -667)
    }
    func testRestoreClampsAnOldFrameToCurrentVisibleDisplay() {
        let result = Layout.restored(CGRect(x: -2000, y: 3000, width: 5000, height: 4000), on: screen)
        XCTAssertEqual(result, screen.visibleFrame)
    }
    func testParkingAcrossRandomFramesKeepsWindowsReachableAndOutOfNeighbors() {
        var screen = screen
        screen.neighbors = [CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        for x in stride(from: -6000.0, through: 6000, by: 120) {
            for width in [160.0, 712, 1424, 2500] {
                let result = Layout.parked(CGRect(x: x, y: -100, width: width, height: 1000), on: screen)
                XCTAssertGreaterThan(result.intersection(screen.frame).width, 0)
                XCTAssertFalse(result.intersects(screen.neighbors[0]))
                XCTAssertGreaterThanOrEqual(result.minY, screen.visibleFrame.minY)
                XCTAssertLessThanOrEqual(result.maxY, screen.visibleFrame.maxY)
            }
        }
    }
}

final class StripTests: XCTestCase {
    func testBackgroundInsertionPreservesFocusWidthsAndScroll() {
        var strip = Strip()
        let first = WindowID(), background = WindowID()
        strip.insert(first, foreground: true, width: .fraction(2.0 / 3))
        strip.scrollOffset = 123
        strip.insert(background, foreground: false)
        XCTAssertEqual(strip.focusedWindow, first)
        XCTAssertEqual(strip.scrollOffset, 123)
        XCTAssertEqual(strip.columns[0].width, .fraction(2.0 / 3))
        XCTAssertEqual(strip.columns[1].windows, [background])
    }
    func testNewWindowOpensRightOfFocusedColumn() {
        var strip = Strip()
        let a = WindowID(), b = WindowID(), c = WindowID()
        strip.insert(a, foreground: true)
        strip.insert(b, foreground: true)
        strip.perform(.focus(.first))
        strip.insert(c, foreground: true)
        XCTAssertEqual(strip.columns.flatMap(\.windows), [a, c, b])
    }
    func testDuplicateWindowsAreIgnored() {
        var strip = Strip()
        let id = WindowID()
        strip.insert(id, foreground: true)
        strip.insert(id, foreground: true)
        XCTAssertEqual(strip.columns.count, 1)
    }
    func testMovePreservesFocusedWindowAndWidths() {
        var strip = Strip()
        let a = WindowID(), b = WindowID()
        strip.insert(a, foreground: true, width: .fraction(1.0 / 3))
        strip.insert(b, foreground: true, width: .fraction(2.0 / 3))
        strip.perform(.move(-1))
        XCTAssertEqual(strip.focusedWindow, b)
        XCTAssertEqual(strip.columns[0].windows, [b])
        XCTAssertEqual(strip.columns[0].width, .fraction(2.0 / 3))
        strip.perform(.move(-1))
        XCTAssertEqual(strip.columns[0].windows, [b])
    }
    func testFocusClampsAndMissingSlotDoesNothing() {
        var strip = Strip()
        let id = WindowID()
        strip.insert(id, foreground: true)
        for action: StripAction in [.focus(.left), .focus(.right), .focus(.slot(8)), .move(1)] {
            strip.perform(action)
            XCTAssertEqual(strip.focusedWindow, id)
        }
    }
    func testWidthPresetCycle() {
        var strip = Strip()
        strip.insert(WindowID(), foreground: true, width: .fraction(1.0 / 3))
        for expected in [0.5, 2.0 / 3, 1.0, 1.0 / 3] {
            strip.perform(.nextWidth)
            XCTAssertEqual(strip.columns[0].width, .fraction(expected))
        }
    }
    func testRemoveFocusedWindowSelectsNearestRemainingColumn() {
        var strip = Strip()
        let a = WindowID(), b = WindowID(), c = WindowID()
        for id in [a, b, c] { strip.insert(id, foreground: true) }
        strip.remove(c)
        XCTAssertEqual(strip.focusedWindow, b)
        strip.remove(b)
        XCTAssertEqual(strip.focusedWindow, a)
        strip.remove(a)
        XCTAssertNil(strip.focusedWindow)
        XCTAssertTrue(strip.columns.isEmpty)
    }
    func testFloatingClassification() {
        XCTAssertTrue(WindowTraits().isTileable)
        XCTAssertFalse(WindowTraits(isStandard: false).isTileable)
        XCTAssertFalse(WindowTraits(canResize: false).isTileable)
        XCTAssertFalse(WindowTraits(canMove: false).isTileable)
        XCTAssertFalse(WindowTraits(isMinimized: true).isTileable)
        XCTAssertFalse(WindowTraits(isFullscreen: true).isTileable)
        XCTAssertFalse(WindowTraits(isOwnWindow: true).isTileable)
        XCTAssertFalse(WindowTraits(hasSheet: true).isTileable)
        XCTAssertFalse(WindowTraits(isFixedSizeApp: true).isTileable)
    }
}
