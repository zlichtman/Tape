import AppKit
import XCTest
@testable import TapeEngine
@testable import TapeRuntime

final class WindowInteractionTests: XCTestCase {
    private let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900))
    private func windows(_ count: Int = 3) -> [WindowSnapshot] {
        (0..<count).map { WindowSnapshot(id: WindowID(), frame: CGRect(x: 40 + 400 * $0, y: 60, width: 380, height: 650), processID: 0, isTileable: true, bundleIdentifier: "fixture", title: "Document \($0)") }
    }
    @MainActor private func fixture() -> (TapeController, TapeSettings, FakeWindows, FakeAnimator, UserDefaults, String) {
        let suite = "TapeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let settings = TapeSettings(defaults: defaults), server = FakeWindows(), animator = FakeAnimator()
        let controller = TapeController(settings: settings, server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: screen, log: { _ in })
        return (controller, settings, server, animator, defaults, suite)
    }
    @MainActor private func waitForScan() async { try? await Task.sleep(nanoseconds: 120_000_000) }
    @MainActor private func observed(_ windows: [WindowSnapshot], _ frames: [WindowID: CGRect]) -> [WindowSnapshot] {
        windows.map { WindowSnapshot(id: $0.id, frame: frames[$0.id] ?? $0.frame, processID: $0.processID, isTileable: true, bundleIdentifier: $0.bundleIdentifier, title: $0.title) }
    }

    @MainActor func testNativeTabAndFocusChangesKeepLoneWindowFullOrExplicitWidth() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows(1), id = list[0].id
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, id)
        XCTAssertEqual(animator.current[id]?.width, 1584)
        await waitForScan()
        server.scans.removeFirst()(observed(list, animator.current), id)
        XCTAssertEqual(animator.current[id]?.width, 1584)
        controller.setWidth(2.0 / 3)
        let explicit = animator.current[id]
        await waitForScan()
        server.scans.removeFirst()(observed(list, animator.current), id)
        XCTAssertEqual(animator.current[id], explicit)
    }
    @MainActor func testCloseRetargetsMotionImmediatelyAndDropsClosedWindow() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        animator.holdsAnimation = true
        controller.perform(.strip(.right))
        let moving = animator.current
        let count = animator.animations.count
        server.onWindowRemoved?(list[1].id)
        XCTAssertEqual(controller.managedCount, 2)
        XCTAssertEqual(animator.animations.count, count + 1)
        XCTAssertNil(animator.animations.last?[list[1].id])
        XCTAssertEqual(animator.starts.last?[list[0].id], moving[list[0].id])
        controller.pause()
        XCTAssertNil(server.restored[list[1].id])
    }
    @MainActor func testDragReordersOnlyOnReleaseAndScanDoesNotFightIt() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        var dragged = animator.current[list[2].id]!
        dragged.origin.x = 8
        let writes = server.writes.count
        server.onWindowInteraction?(list[2].id, dragged, .move, false)
        server.onChange?(); await waitForScan()
        XCTAssertEqual(server.writes.count, writes)
        XCTAssertEqual(controller.windowChoices.map(\.id), list.map(\.id))
        server.onWindowInteraction?(list[2].id, dragged, .move, true)
        XCTAssertEqual(controller.windowChoices.map(\.id), [list[2].id, list[0].id, list[1].id])
        XCTAssertTrue(server.focused.isEmpty, "Dragging does not activate a different app")
    }
    @MainActor func testSharedResizeLeavesSourceUnderPointerAndSizesCompanions() async {
        let (controller, settings, server, animator, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        settings.sharedWidths = true
        var dragged = animator.current[list[0].id]!
        dragged.size.width = 600
        server.onWindowInteraction?(list[0].id, dragged, .resize, false)
        XCTAssertNil(server.writes.last?[list[0].id])
        XCTAssertTrue(server.writes.last!.values.allSatisfy { $0.width == 600 })
        server.onWindowInteraction?(list[0].id, dragged, .resize, true)
        XCTAssertTrue(animator.current.values.allSatisfy { $0.width == 600 })
        controller.setAllWidths(1.0 / 3)
        XCTAssertTrue(animator.current.values.allSatisfy { abs($0.width - 528) < 0.01 })
    }
    @MainActor func testWindowLockRestoresOthersAndLeavesFutureWindowsAlone() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        controller.setManageAllWindows(false)
        XCTAssertEqual(controller.windowChoices.map(\.id), [list[0].id])
        XCTAssertTrue(server.writes.contains { $0[list[1].id] == list[1].frame && $0[list[2].id] == list[2].frame })
        await waitForScan()
        let future = windows(1)[0]
        server.scans.removeLast()(observed(list, animator.current) + [future], list[0].id)
        XCTAssertEqual(controller.managedCount, 1)
        controller.setWindowManaged(list[1].id, true)
        XCTAssertEqual(controller.managedCount, 2)
        controller.setWindowManaged(list[1].id, false)
        let baseline = server.writes.last
        controller.setAllWidths(1)
        XCTAssertNil(server.writes.last?[list[1].id])
        XCTAssertNotNil(baseline)
        controller.pause()
        XCTAssertEqual(Set(server.restored.keys), [list[0].id])
    }
    @MainActor func testStackTabsSelectionReorderAndTemporaryDisappearance() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[1].id)
        controller.perform(.strip(.joinLeft))
        XCTAssertEqual(animator.current[list[0].id]?.width, animator.current[list[1].id]?.width)
        XCTAssertLessThan(animator.current[list[0].id]!.maxY, animator.current[list[1].id]!.minY)
        controller.perform(.strip(.toggleMode))
        XCTAssertEqual(animator.current[list[0].id], animator.current[list[1].id])
        XCTAssertEqual(controller.tabGroups.first?.windows.map(\.id), [list[0].id, list[1].id])
        controller.reorderTab(list[1].id, before: list[0].id)
        controller.chooseWindow(list[0].id)
        XCTAssertEqual(controller.windowChoices.first(where: \.selected)?.id, list[0].id)
        XCTAssertEqual(server.raised.last, list[0].id)
        await waitForScan()
        let frames = animator.current
        server.scans.removeLast()(observed([list[0], list[2]], frames), list[0].id)
        await waitForScan()
        server.scans.removeLast()(observed(list, frames), list[0].id)
        XCTAssertEqual(controller.tabGroups.first?.windows.map(\.id), [list[1].id, list[0].id])
        server.onWindowRemoved?(list[0].id)
        XCTAssertEqual(controller.managedCount, 2)
        XCTAssertNil(controller.tabGroups.first, "A single remaining tab becomes a plain window")
    }
    func testStackActionsPreserveMembershipOrderWidthsAndHeightBounds() {
        let a = WindowID(), b = WindowID(), c = WindowID()
        var strip = Strip()
        for id in [a, b, c] { strip.insert(id, foreground: true) }
        strip.perform(.join(-1)); strip.perform(.join(-1))
        XCTAssertEqual(strip.columns.count, 2)
        XCTAssertEqual(Set(strip.columns.flatMap(\.windows)), [a, b, c])
        strip.select(b); strip.perform(.join(-1))
        XCTAssertEqual(strip.columns.count, 1)
        strip.perform(.adjustHeight(2))
        let frames = Layout.frames(for: strip, screen: screen, options: LayoutOptions(gap: 2000))
        XCTAssertTrue(frames.values.allSatisfy { $0.height > 0 && screen.visibleFrame.contains($0) })
        strip.perform(.equalHeights)
        XCTAssertTrue(strip.columns[0].heightWeights.isEmpty)
        strip.perform(.detach)
        XCTAssertEqual(Set(strip.columns.flatMap(\.windows)), [a, b, c])
        XCTAssertEqual(strip.focusedWindow, b)
    }

    @MainActor func testStackThatExceedsAppMinimumHeightsSeparatesInsteadOfOverlapping() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[1].id)
        controller.perform(.strip(.joinLeft))
        await waitForScan()
        var actual = animator.current
        actual[list[0].id]?.size.height = 650
        actual[list[1].id]?.size.height = 650
        server.scans.removeLast()(observed(list, actual), list[1].id)
        XCTAssertEqual(controller.windowChoices.count, 3)
        XCTAssertEqual(animator.current[list[0].id]?.height, 884)
        XCTAssertEqual(animator.current[list[1].id]?.height, 884)
        XCTAssertNotEqual(animator.current[list[0].id]?.minX, animator.current[list[1].id]?.minX)
        XCTAssertEqual(controller.windowChoices.first(where: \.selected)?.id, list[1].id)
    }

    @MainActor func testEdgeDragScrollsCompanionsWithoutWritingTheDraggedWindow() async {
        let suite = "TapeTests.edge." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = FakeWindows(), animator = FakeAnimator(), clock = TestFrameClock()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: screen, scrollClock: clock, log: { _ in })
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[2].id)
        // Column 0 is parked off-screen and only moves once the scroll passes its sliver,
        // which depends on timer slack; the visible companion moves on any tick.
        let before = animator.current[list[1].id]!.minX
        var frame = animator.current[list[2].id]!
        frame.origin.x -= 100
        server.pointerPosition = CGPoint(x: 8, y: 100)
        server.onWindowInteraction?(list[2].id, frame, .move, false)
        try? await Task.sleep(nanoseconds: 20_000_000)
        clock.tick?()
        XCTAssertNil(server.writes.last?[list[2].id])
        XCTAssertGreaterThan(server.writes.last![list[1].id]!.minX, before)
        server.onWindowInteraction?(list[2].id, frame, .move, true)
        XCTAssertNil(clock.tick)
    }

    @MainActor func testClosingTheDraggedWindowStopsItsEdgeBrowsingClock() async {
        let suite = "TapeTests.close-drag." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = FakeWindows(), animator = FakeAnimator(), clock = TestFrameClock()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: screen, scrollClock: clock, log: { _ in })
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[2].id)
        var frame = animator.current[list[2].id]!
        frame.origin.x -= 100
        server.onWindowInteraction?(list[2].id, frame, .move, false)
        XCTAssertNotNil(clock.tick)
        server.onWindowRemoved?(list[2].id)
        XCTAssertNil(clock.tick, "A display link left running fires at the refresh rate indefinitely")
    }

    @MainActor func testQuitRestoresWindowMissingFromLatestScanAfterOffscreenBrowsing() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        controller.chooseWindow(list[2].id)
        await waitForScan()
        server.scans.removeLast()(observed([list[1], list[2]], animator.current), list[2].id)
        XCTAssertEqual(controller.managedCount, 2, "The omitted window can be hidden or unavailable")
        var finished = false
        controller.shutdown { finished = true }
        XCTAssertTrue(finished)
        XCTAssertEqual(server.restored[list[0].id], list[0].frame)
        XCTAssertTrue(server.restored.values.allSatisfy { screen.visibleFrame.contains($0) })
    }

    @MainActor func testHiddenWindowReturnsToItsSlotRatherThanBesideTheFocusedColumn() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows(5), order = list.map(\.id)
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        XCTAssertEqual(controller.windowChoices.map(\.id), order)
        // Hide or minimize the fourth window, then bring it back.
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list.filter { $0.id != list[3].id }, animator.current), list[0].id)
        XCTAssertEqual(controller.windowChoices.map(\.id), [order[0], order[1], order[2], order[4]])
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, animator.current), list[0].id)
        XCTAssertEqual(controller.windowChoices.map(\.id), order)
        // An app with two windows hides and unhides; neither the slots nor their order change.
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed([list[0], list[2], list[4]], animator.current), list[0].id)
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, animator.current), list[0].id)
        XCTAssertEqual(controller.windowChoices.map(\.id), order)
    }

    @MainActor func testSwitchingDesktopsAndBackKeepsTheStripOrder() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows(6), order = list.map(\.id)
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[2].id)
        // Parked windows keep a six-point sliver, so a narrower column parks further right.
        controller.chooseWindow(list[0].id); controller.setWidth(1.0 / 3)
        controller.chooseWindow(list[1].id); controller.setWidth(2.0 / 3)
        controller.perform(.strip(.last))
        let parked = animator.current
        XCTAssertGreaterThan(Set(parked.values.map(\.minX)).count, 1)
        // Another desktop has none of these windows; returning reports their parked frames,
        // which no longer sort left to right.
        server.onDesktopChange?(); await waitForScan()
        server.scans.removeLast()([], nil)
        XCTAssertEqual(controller.managedCount, 0)
        server.onDesktopChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, parked), list[5].id)
        XCTAssertEqual(controller.windowChoices.map(\.id), order)
    }

    @MainActor func testSeveralNewWindowsKeepTheirLeftToRightOrderAfterTheFocusedColumn() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows(5)
        controller.resume(); await waitForScan(); server.scans.removeFirst()(Array(list.prefix(2)), list[0].id)
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, animator.current), list[0].id)
        XCTAssertEqual(controller.windowChoices.map(\.id), [list[0].id, list[2].id, list[3].id, list[4].id, list[1].id])
    }

    @MainActor func testAWindowListedTwiceJoinsOnce() async {
        let (controller, _, server, _, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list + [list[1]], list[0].id)
        XCTAssertEqual(controller.windowChoices.map(\.id), list.map(\.id))
    }

    @MainActor func testUnchangedScansAndDragFramesDoNotRepublishStatus() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { controller.pause(); defaults.removePersistentDomain(forName: suite) }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, animator.current), list[0].id)
        var changes = 0
        let subscription = controller.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, animator.current), list[0].id)
        XCTAssertEqual(changes, 0, "Settings re-renders on every published assignment")
        var frame = animator.current[list[1].id]!
        for step in 1...5 {
            frame.size.width += 1
            server.onWindowInteraction?(list[1].id, frame, .resize, step == 5)
        }
        XCTAssertEqual(changes, 0)
    }

    @MainActor func testPauseRestoresHiddenWindowsButNotExplicitlyReleasedOrClosedWindows() async {
        let (controller, _, server, animator, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let list = windows(4)
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        controller.setWindowManaged(list[1].id, false)
        server.onWindowRemoved?(list[2].id)
        await waitForScan()
        server.scans.removeLast()(observed([list[1], list[3]], animator.current), list[3].id)
        controller.pause()
        XCTAssertEqual(server.restored[list[0].id], list[0].frame)
        XCTAssertNil(server.restored[list[1].id])
        XCTAssertNil(server.restored[list[2].id])
        XCTAssertEqual(server.restored[list[3].id], Layout.restored(list[3].frame, on: screen))
    }

    func testRestorationWaitsBehindInFlightParkedWriteAndIsTheLastFrame() {
        let started = expectation(description: "parked write in flight"), settled = expectation(description: "restored")
        let release = DispatchSemaphore(value: 0), lock = NSLock()
        var frames: [CGRect] = []
        let id = WindowID(), parked = CGRect(x: -500, y: 50, width: 506, height: 700), restored = CGRect(x: 40, y: 60, width: 380, height: 650)
        let queue = FrameWriteQueue { job in
            if !job.restoring { started.fulfill(); _ = release.wait(timeout: .now() + 2) }
            lock.lock(); frames.append(job.frame); lock.unlock()
        }
        queue.enqueue([(1, FrameWrite(id: id, frame: parked, generation: 0))])
        wait(for: [started], timeout: 1)
        queue.cancelPending()
        queue.enqueue([(1, FrameWrite(id: id, frame: restored, generation: 1, restoring: true))])
        queue.whenIdle { settled.fulfill() }
        release.signal()
        wait(for: [settled], timeout: 1)
        lock.lock(); let written = frames; lock.unlock()
        XCTAssertEqual(written, [parked, restored])
    }
}
