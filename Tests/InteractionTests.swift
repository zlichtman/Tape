import XCTest
import CoreGraphics
import Carbon
@testable import TapeRuntime
@testable import TapeEngine

final class InteractionTests: XCTestCase {
    func testCompactKeyboardEndShortcutsKeepExistingBindings() {
        let first = HotKeyBinding.defaults.filter { $0.action == .strip(.first) }
        let last = HotKeyBinding.defaults.filter { $0.action == .strip(.last) }
        XCTAssertEqual(Set(first.map(\.keyCode)), Set([UInt32(kVK_Home), UInt32(kVK_ANSI_LeftBracket)]))
        XCTAssertEqual(Set(last.map(\.keyCode)), Set([UInt32(kVK_End), UInt32(kVK_ANSI_RightBracket)]))
        let signatures = HotKeyBinding.defaults.map { "\($0.keyCode):\($0.modifiers)" }
        XCTAssertEqual(Set(signatures).count, signatures.count, "Default commands must not compete for a binding")
    }
    func testResizeHappensOnceWhileTheWindowSlides() {
        let from = CGRect(x: 0, y: 20, width: 900, height: 700)
        let to = CGRect(x: 450, y: 20, width: 450, height: 700)
        let frames = (0...60).map { FrameMotion.interpolate(from: from, to: to, progress: Double($0) / 60) }
        XCTAssertEqual(frames.first?.minX, from.minX)
        XCTAssertEqual(frames.last, to)
        XCTAssertTrue(frames.allSatisfy { $0.size == to.size })
        XCTAssertFalse(FrameMotion.needsResize(from: frames[0], to: frames[1]))
        XCTAssertTrue(FrameMotion.needsMove(from: frames[0], to: frames[1]))
        XCTAssertTrue(FrameMotion.needsResize(from: from, to: frames[0]))
    }
    func testStaleFocusDoesNotUndoRapidKeyboardNavigation() {
        let ids = (0..<3).map { _ in WindowID() }
        var intent = FocusIntent()
        intent.request(ids[1], now: 0)
        intent.request(ids[2], now: 0.1)
        XCTAssertEqual(intent.resolve(observed: ids[0], available: Set(ids), now: 0.2), ids[2])
        XCTAssertEqual(intent.resolve(observed: ids[1], available: Set(ids), now: 0.3), ids[2])
        XCTAssertEqual(intent.resolve(observed: ids[2], available: Set(ids), now: 0.4), ids[2])
        XCTAssertEqual(intent.resolve(observed: ids[0], available: Set(ids), now: 0.5), ids[0])
    }
    func testFocusIntentExpiresOrReleasesAClosedWindow() {
        let a = WindowID(), b = WindowID()
        var intent = FocusIntent()
        intent.request(b, now: 0)
        XCTAssertEqual(intent.resolve(observed: a, available: [a, b], now: 1), a)
        intent.request(b, now: 2)
        XCTAssertEqual(intent.resolve(observed: a, available: [a], now: 2.1), a)
    }
    func testAppChoicesWorkInBothModesAndPersist() throws {
        var policy = AppPolicy()
        XCTAssertTrue(policy.manages("browser"))
        policy.setManaged(false, bundleID: "browser")
        XCTAssertFalse(policy.manages("browser"))
        XCTAssertTrue(policy.manages("notes"))
        policy.setManaged(true, bundleID: "notes")
        policy.manageAll = false
        XCTAssertTrue(policy.manages("notes"))
        XCTAssertFalse(policy.manages("new-app"))
        XCTAssertFalse(policy.manages(nil))
        let copy = try JSONDecoder().decode(AppPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertEqual(copy, policy)
    }
    func testExplicitWidthPreservesOtherColumns() {
        let a = WindowID(), b = WindowID()
        var strip = Strip(); strip.insert(a, foreground: true); strip.insert(b, foreground: false)
        strip.perform(.setWidth(2.0 / 3))
        XCTAssertEqual(strip.columns[0].width, .fraction(2.0 / 3))
        XCTAssertEqual(strip.columns[1].width, .fraction(0.5))
        strip.perform(.setWidth(.nan))
        XCTAssertEqual(strip.columns[0].width, .fraction(2.0 / 3))
    }
}
