import XCTest
import AppKit
import ApplicationServices
@testable import TapeEngine
@testable import TapeRuntime

final class DiscoveryTests: XCTestCase {
    func testMenuBarAppsWithNormalWindowsAreDiscoverable() {
        XCTAssertTrue(WindowDiscovery.includesApp(policy: .regular, isOwnApp: false))
        XCTAssertTrue(WindowDiscovery.includesApp(policy: .accessory, isOwnApp: false))
        XCTAssertFalse(WindowDiscovery.includesApp(policy: .prohibited, isOwnApp: false))
        XCTAssertFalse(WindowDiscovery.includesApp(policy: .accessory, isOwnApp: true))
    }
    func testNormalCustomWindowsRemainEligibleWhileDialogsStayFloating() {
        for subrole in [nil, kAXUnknownSubrole as String, kAXStandardWindowSubrole as String] {
            let normal = WindowDiscovery.isNormalWindow(role: kAXWindowRole as String, subrole: subrole)
            XCTAssertTrue(normal)
            XCTAssertTrue(WindowTraits(isStandard: normal, canMove: true, canResize: true).isTileable)
            XCTAssertFalse(WindowTraits(isStandard: normal, canMove: true, canResize: false).isTileable)
        }
        for subrole in [kAXDialogSubrole, kAXSystemDialogSubrole, kAXFloatingWindowSubrole] {
            XCTAssertFalse(WindowDiscovery.isNormalWindow(role: kAXWindowRole as String, subrole: subrole as String))
        }
        XCTAssertFalse(WindowDiscovery.isNormalWindow(role: kAXSheetRole as String, subrole: nil))
    }
    func testIndependentFrameReadsAllowSmallDriftWithoutMatchingOtherWindows() {
        let frame = CGRect(x: 100, y: 60, width: 700, height: 800)
        XCTAssertTrue(WindowDiscovery.visibleMatch(frame, frame.offsetBy(dx: 4, dy: 4)))
        XCTAssertFalse(WindowDiscovery.visibleMatch(frame, frame.offsetBy(dx: 40, dy: 0)))
        XCTAssertFalse(WindowDiscovery.visibleMatch(frame, CGRect(x: 100, y: 60, width: 200, height: 100)))
    }
    func testCenteredEdgeDoesNotJumpOnFirstScrollPixel() {
        let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900))
        let options = LayoutOptions(centering: .always)
        var strip = Strip()
        for _ in 0..<3 { strip.insert(WindowID(), foreground: false) }
        strip.focusedWindow = strip.columns[0].windows[0]
        strip.scrollOffset = Layout.revealedOffset(for: strip, screen: screen, options: options)
        let start = strip.scrollOffset
        XCTAssertLessThan(start, 0)
        XCTAssertEqual(Layout.scrolledOffset(for: strip, by: 1, screen: screen, options: options), start + 1)
        XCTAssertEqual(Layout.scrolledOffset(for: strip, by: -1, screen: screen, options: options), start)
    }
}
