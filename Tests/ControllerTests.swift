import XCTest
import AppKit
@testable import TapeEngine
@testable import TapeRuntime

final class FakeWindows: WindowServer {
    var onChange: (() -> Void)?
    var onStall: (() -> Void)?
    var onFocusChange: ((WindowID) -> Void)?
    var onDesktopChange: (() -> Void)?
    var onWindowRemoved: ((WindowID) -> Void)?
    var onWindowInteraction: ((WindowID, CGRect, WindowInteraction, Bool) -> Void)?
    var pointerPosition: CGPoint?
    var scanPolicies: [AppPolicy] = []
    var scans: [([WindowSnapshot], WindowID?) -> Void] = []
    var writes: [[WindowID: CGRect]] = []
    var cancellations = 0
    var focused: [WindowID] = []
    var raised: [WindowID] = []
    var restored: [WindowID: CGRect] = [:]
    func start() {}
    func stop() {}
    func scan(policy: AppPolicy, completion: @escaping ([WindowSnapshot], WindowID?) -> Void) { scanPolicies.append(policy); scans.append(completion) }
    func apply(frames: [WindowID: CGRect]) { writes.append(frames) }
    func cancelPendingWrites() { cancellations += 1 }
    func settle(completion: @escaping () -> Void) { completion() }
    func focus(_ id: WindowID, activate: Bool) { if activate { focused.append(id) } }
    func raise(_ ids: [WindowID], preservingFocus focused: WindowID?) { raised += ids.filter { $0 != focused }; if let focused { raised.append(focused) } }
    func restore(frames: [WindowID: CGRect], completion: @escaping () -> Void) { restored = frames; completion() }
}
final class FakeAnimator: WindowAnimator {
    var current: [WindowID: CGRect] = [:]
    var isAnimating = false
    var holdsAnimation = false
    var animations: [[WindowID: CGRect]] = []
    var starts: [[WindowID: CGRect]] = []
    func cancel() { current.removeAll(); isAnimating = false }
    func animate(to frames: [WindowID: CGRect], from initial: [WindowID: CGRect], screen: NSScreen?, geometry: ScreenGeometry, reduceMotion: Bool, write: @escaping ([WindowID: CGRect]) -> Void, completion: @escaping () -> Void) {
        animations.append(frames); starts.append(initial)
        if holdsAnimation { isAnimating = true } else { current = frames; write(frames); completion() }
    }
}
final class ControllerTests: XCTestCase {
    @MainActor func testStartupOrderAndRapidFocusAreStable() async {
        let suite = "TapeTests." + UUID().uuidString, defaults = UserDefaults(suiteName: "TapeTests.temp")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.temp") }
        let server = FakeWindows()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: FakeAnimator(), permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        let windows = snapshots()
        controller.resume(); await yieldToMain()
        XCTAssertFalse(server.scans.isEmpty, suite)
        server.scans.removeFirst()(windows, windows[0].id)
        XCTAssertEqual(controller.windowChoices.map(\.id), windows.map(\.id))
        controller.perform(.strip(.right)); controller.perform(.strip(.right))
        XCTAssertEqual(server.focused, [windows[1].id, windows[2].id])
        server.onFocusChange?(windows[0].id)
        XCTAssertEqual(controller.windowChoices.first(where: \.selected)?.id, windows[2].id)
        controller.pause()
        XCTAssertEqual(server.restored, Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) }))
    }
    @MainActor func testExcludingAnAppRestoresItAndStopsManagingIt() async {
        let name = "TapeTests." + UUID().uuidString, defaults = UserDefaults(suiteName: "TapeTests.rules")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.rules") }
        let settings = TapeSettings(defaults: defaults), server = FakeWindows(), windows = snapshots()
        let controller = TapeController(settings: settings, server: server, animator: FakeAnimator(), permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain()
        XCTAssertFalse(server.scans.isEmpty, name)
        server.scans.removeFirst()(windows, windows[0].id)
        settings.appPolicy.setManaged(false, bundleID: "app.1")
        await yieldToMain()
        XCTAssertFalse(controller.windowChoices.map(\.id).contains(windows[1].id))
        XCTAssertTrue(server.writes.contains { $0[windows[1].id] == windows[1].frame })
        controller.pause()
        XCTAssertNil(server.restored[windows[1].id], "Pause must leave the deselected app alone")
    }
    @MainActor func testOldScanCannotUndoAKeyboardAction() async {
        let defaults = UserDefaults(suiteName: "TapeTests.scan")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.scan") }
        let server = FakeWindows(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: FakeAnimator(), permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        await yieldToMain()
        guard !server.scans.isEmpty else { return XCTFail("Expected reconciliation scan") }
        let old = server.scans.removeFirst()
        controller.perform(.strip(.right))
        old(windows, windows[0].id)
        XCTAssertEqual(controller.windowChoices.first(where: \.selected)?.id, windows[1].id)
        controller.pause()
    }
    @MainActor func testOnlySelectedAppsReachTheWindowScan() async {
        let name = "TapeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = TapeSettings(defaults: defaults)
        settings.appPolicy.manageAll = false
        settings.appPolicy.setManaged(true, bundleID: "app.1")
        let server = FakeWindows(), windows = snapshots()
        let controller = TapeController(settings: settings, server: server, animator: FakeAnimator(), permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain()
        XCTAssertEqual(server.scanPolicies.last, settings.appPolicy)
        server.scans.removeFirst()(windows, windows[1].id)
        XCTAssertEqual(controller.windowChoices.map(\.id), [windows[1].id])
        controller.pause()
        XCTAssertEqual(server.restored, [windows[1].id: windows[1].frame])
    }
    @MainActor func testManualMoveIsCorrectedEvenWhenTargetsAreUnchanged() async {
        let name = "TapeTests." + UUID().uuidString, defaults = UserDefaults(suiteName: "TapeTests.manual")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.manual") }
        let server = FakeWindows(), animator = FakeAnimator(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        await yieldToMain()
        XCTAssertFalse(server.scans.isEmpty, name)
        let target = animator.current
        let displaced = windows.map { window -> WindowSnapshot in
            var frame = target[window.id]!
            frame.origin.y += 40
            return WindowSnapshot(id: window.id, frame: frame, processID: window.processID, isTileable: true, bundleIdentifier: window.bundleIdentifier)
        }
        let count = animator.animations.count
        server.scans.removeFirst()(displaced, windows[0].id)
        XCTAssertEqual(animator.animations.count, count + 1)
        XCTAssertEqual(animator.current, target)
        controller.pause()
    }
    @MainActor func testRejectedFramesDoNotStartAnEndlessCorrectionLoop() async {
        let defaults = UserDefaults(suiteName: "TapeTests.refused")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.refused") }
        let server = FakeWindows(), animator = FakeAnimator(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        await yieldToMain()
        let count = animator.animations.count
        // The app reports exactly the same frame after declining the first write.
        server.scans.removeFirst()(windows, windows[0].id)
        XCTAssertEqual(animator.animations.count, count)
        await yieldToMain()
        XCTAssertTrue(server.scans.isEmpty)
        controller.pause()
    }
    @MainActor func testReversalUsesCurrentAnimationPosition() async {
        let defaults = UserDefaults(suiteName: "TapeTests.reverse")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.reverse") }
        let server = FakeWindows(), animator = FakeAnimator(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        await yieldToMain()
        let settled = windows.map { window in
            WindowSnapshot(id: window.id, frame: animator.current[window.id]!, processID: window.processID, isTileable: true, bundleIdentifier: window.bundleIdentifier)
        }
        server.scans.removeFirst()(settled, windows[0].id)
        animator.holdsAnimation = true
        controller.setWidth(0.75)
        let wide = animator.animations.last!
        animator.current = wide
        let count = animator.animations.count
        controller.setWidth(0.5)
        XCTAssertEqual(animator.animations.count, count + 1, "Returning to the scanned width must interrupt motion")
        XCTAssertEqual(animator.starts.last, wide)
        // Even if the new target happens to equal the current step, stop the old motion.
        animator.current = wide
        let reversedCount = animator.animations.count
        controller.setWidth(0.75)
        XCTAssertEqual(animator.animations.count, reversedCount + 1)
        controller.pause()
    }
    @MainActor func testPreviousRunScanCannotReleaseCurrentScan() async {
        let defaults = UserDefaults(suiteName: "TapeTests.restart")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.restart") }
        let server = FakeWindows(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: FakeAnimator(), permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain()
        let previousRun = server.scans.removeFirst()
        controller.pause(); controller.resume(); await yieldToMain()
        XCTAssertEqual(server.scans.count, 1)
        previousRun(windows, windows[0].id)
        server.onChange?(); await yieldToMain()
        XCTAssertEqual(server.scans.count, 1, "A stale callback must not allow overlapping scans")
        server.scans.removeFirst()(windows, windows[0].id)
        XCTAssertEqual(controller.managedCount, 3)
        controller.pause()
    }
    @MainActor func testScrollingCoalescesAtDisplayRefreshWithoutActivatingApps() async {
        let name = "TapeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let server = FakeWindows(), animator = FakeAnimator(), clock = TestFrameClock(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: geometry, scrollClock: clock, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        let selected = controller.windowChoices.first(where: \.selected)?.id
        let writes = server.writes.count, animations = animator.animations.count
        for _ in 0..<10 { controller.scroll(by: 10) }
        XCTAssertEqual(server.writes.count, writes, "Input should accumulate until display refresh")
        clock.tick?()
        XCTAssertEqual(server.writes.count, writes + 1)
        XCTAssertEqual(animator.animations.count, animations, "No easing animation for each scroll event")
        XCTAssertTrue(server.focused.isEmpty, "Browsing must never activate an app")
        XCTAssertEqual(controller.windowChoices.first(where: \.selected)?.id, selected)
        let before = server.writes.last!
        controller.scroll(by: 50); clock.tick?()
        XCTAssertLessThan(server.writes.last![windows[0].id]!.minX, before[windows[0].id]!.minX)
        let browsed = server.writes.last!
        controller.perform(.strip(.right))
        controller.perform(.strip(.right)) // The third column needs a viewport move.
        XCTAssertEqual(animator.starts.last, browsed, "Keyboard navigation starts from the browsed positions")
        XCTAssertEqual(server.focused, [windows[1].id, windows[2].id])
        XCTAssertNil(clock.tick)
        controller.scroll(by: 20) // Pause must discard this unflushed step.
        let writesBeforePause = server.writes.count
        controller.pause()
        XCTAssertEqual(server.writes.count, writesBeforePause)
        let pausedWrites = server.writes.count
        controller.scroll(by: 20); clock.tick?()
        XCTAssertEqual(server.writes.count, pausedWrites)
        XCTAssertNil(clock.tick)
    }
    @MainActor func testAppMinimumWidthIsLearnedAfterTrackpadBrowsing() async {
        let name = "TapeTests." + UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let server = FakeWindows(), animator = FakeAnimator(), clock = TestFrameClock(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: geometry, scrollClock: clock, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        controller.setWidth(1.0 / 3)
        controller.scroll(by: 20); clock.tick?()
        XCTAssertTrue(animator.current.isEmpty)
        await yieldToMain(); await yieldToMain(); await yieldToMain()
        guard !server.scans.isEmpty else { return XCTFail("Expected post-scroll reconciliation") }
        let requested = server.writes.last!
        let actual = windows.map { window -> WindowSnapshot in
            var frame = requested[window.id]!
            if window.id == windows[0].id { frame.size.width = 900 }
            return WindowSnapshot(id: window.id, frame: frame, processID: window.processID, isTileable: true, bundleIdentifier: window.bundleIdentifier)
        }
        server.scans.removeLast()(actual, windows[0].id)
        XCTAssertEqual(animator.current[windows[0].id]?.width, 900)
        controller.pause()
    }
    private var geometry: ScreenGeometry { ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900)) }
    private func snapshots() -> [WindowSnapshot] {
        (0..<3).map { WindowSnapshot(id: WindowID(), frame: CGRect(x: 30 + $0 * 450, y: 50, width: 400, height: 700), processID: 0, isTileable: true, bundleIdentifier: "app.\($0)") }
    }
    @MainActor private func yieldToMain() async { try? await Task.sleep(nanoseconds: 100_000_000) }
}
