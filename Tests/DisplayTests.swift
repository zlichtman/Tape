import AppKit
import XCTest

@testable import TapeEngine
@testable import TapeRuntime

final class DisplayTests: XCTestCase {
    private var a: TapeDisplay {
        TapeDisplay(
            id: "a", name: "Built-in",
            geometry: ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
                visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900)))
    }
    private var b: TapeDisplay {
        TapeDisplay(
            id: "b", name: "External",
            geometry: ScreenGeometry(
                frame: CGRect(x: 1600, y: 0, width: 1600, height: 1000),
                visibleFrame: CGRect(x: 1600, y: 30, width: 1600, height: 900)))
    }
    private func windows(on display: TapeDisplay, count: Int = 3) -> [WindowSnapshot] {
        (0..<count).map {
            WindowSnapshot(
                id: WindowID(),
                frame: CGRect(
                    x: display.geometry.frame.minX + 30 + Double($0) * 450, y: 50, width: 400, height: 700),
                processID: 0, isTileable: true, bundleIdentifier: "fixture")
        }
    }
    @MainActor private func pauseForScan() async { try? await Task.sleep(nanoseconds: 300_000_000) }
    private func observed(_ windows: [WindowSnapshot], server: FakeWindows) -> [WindowSnapshot] {
        var frames: [WindowID: CGRect] = [:]
        for write in server.writes { frames.merge(write) { _, last in last } }
        return windows.map {
            WindowSnapshot(
                id: $0.id, frame: frames[$0.id] ?? $0.frame, processID: $0.processID,
                isTileable: $0.isTileable, bundleIdentifier: $0.bundleIdentifier)
        }
    }
    private func completeLatest(_ server: FakeWindows, windows: [WindowSnapshot], focus: WindowID?) {
        guard let completion = server.scans.last else { return XCTFail("Expected a scan") }
        server.scans.removeAll()
        completion(windows, focus)
    }

    func testOwnershipUsesAreaAndKeepsStableBoundaryTies() {
        let boundary = CGRect(x: 1400, y: 50, width: 400, height: 600)
        XCTAssertEqual(DisplayLayout.owner(of: boundary, in: [a, b], previous: "b"), "b")
        XCTAssertEqual(
            DisplayLayout.owner(of: boundary.offsetBy(dx: 1, dy: 0), in: [a, b], previous: "a"), "b")
        XCTAssertEqual(
            DisplayLayout.owner(of: boundary.offsetBy(dx: -1, dy: 0), in: [a, b], previous: "b"), "a")
        XCTAssertEqual(DisplayLayout.at(CGPoint(x: 1800, y: 100), in: [a, b]), "b")
    }
    func testNegativeAndStackedDisplaysAndDisconnectedFallback() {
        let left = TapeDisplay(
            id: "left", name: "Left",
            geometry: ScreenGeometry(
                frame: CGRect(x: -1600, y: 0, width: 1600, height: 1000),
                visibleFrame: CGRect(x: -1600, y: 30, width: 1600, height: 900)))
        let top = TapeDisplay(
            id: "top", name: "Top",
            geometry: ScreenGeometry(
                frame: CGRect(x: 0, y: -1000, width: 1600, height: 1000),
                visibleFrame: CGRect(x: 0, y: -970, width: 1600, height: 900)))
        XCTAssertEqual(
            DisplayLayout.owner(of: CGRect(x: -1400, y: 100, width: 500, height: 600), in: [a, left, top]),
            "left")
        XCTAssertEqual(
            DisplayLayout.owner(of: CGRect(x: 100, y: -900, width: 500, height: 600), in: [a, left, top]),
            "top")
        XCTAssertEqual(
            DisplayLayout.owner(of: CGRect(x: 1900, y: 100, width: 500, height: 600), in: [a]), "a")
        let geometry = DisplayLayout.geometry(for: a, in: [a, left, top])
        XCTAssertEqual(geometry.neighbors.count, 2)
        XCTAssertNil(DisplayLayout.owner(of: .zero, in: []))
    }
    func testNextDisplaySkipsDisabledAndRequiresAnotherDestination() {
        let c = TapeDisplay(id: "c", name: "Third", geometry: b.geometry)
        XCTAssertEqual(DisplayLayout.next(after: "a", in: [a, b, c], excluding: ["b"]), "c")
        XCTAssertEqual(DisplayLayout.next(after: "c", in: [a, b, c], excluding: ["b"]), "a")
        XCTAssertNil(DisplayLayout.next(after: "a", in: [a, b], excluding: ["b"]))
    }
    func testRemovingTailWindowsCannotLeaveTheViewportPastTheStrip() {
        var strip = Strip()
        for _ in 0..<10 { strip.insert(WindowID(), foreground: false) }
        strip.focusedWindow = strip.columns[0].windows[0]
        strip.scrollOffset = Layout.scrolledOffset(
            for: strip, by: 100_000, screen: a.geometry, options: LayoutOptions())
        while strip.columns.count > 2 { strip.remove(strip.columns.last!.windows[0]) }
        let offset = Layout.constrainedOffset(for: strip, screen: a.geometry, options: LayoutOptions())
        strip.scrollOffset = offset
        XCTAssertTrue(
            Layout.columnRects(for: strip, screen: a.geometry, options: LayoutOptions()).contains {
                a.geometry.visibleFrame.intersection($0).width > 300
            })
    }
    @MainActor func testMirroringCreatesOneDrawableStrip() {
        let defaults = UserDefaults(suiteName: "TapeTests.mirror")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.mirror") }
        let mirror = TapeDisplay(id: "mirror", name: "Mirror", geometry: a.geometry)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: FakeWindows(), animator: FakeAnimator(),
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, mirror],
            animatorFactory: { FakeAnimator() }, clockFactory: { TestFrameClock() })
        XCTAssertEqual(controller.displayChoices.map(\.id), ["a"])
        XCTAssertFalse(controller.canSendToDisplay)
    }
    @MainActor func testTwoDisplaysHaveIndependentWritesAndBrowsingDoesNotMoveFocus() async {
        let name = "TapeTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: "TapeTests.multiple")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.multiple") }
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let ca = TestFrameClock()
        let cb = TestFrameClock()
        let wa = windows(on: a)
        let wb = windows(on: b)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, scrollClock: ca, log: { _ in },
            displays: [a, b], animatorFactory: { ab }, clockFactory: { cb })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        XCTAssertEqual(controller.managedCount, 6, name)
        XCTAssertEqual(controller.displayChoices.map(\.windowCount), [3, 3])
        XCTAssertEqual(Set(aa.current.keys), Set(wa.map(\.id)))
        XCTAssertEqual(Set(ab.current.keys), Set(wb.map(\.id)))
        XCTAssertTrue(aa.current.values.allSatisfy { a.geometry.frame.contains($0) })
        XCTAssertTrue(
            ab.current.values.allSatisfy {
                b.geometry.frame.intersects($0) && !a.geometry.frame.intersects($0)
            })
        let beforeA = aa.current
        controller.scroll(by: 150, at: CGPoint(x: 1800, y: 100))
        cb.tick?()
        XCTAssertEqual(Set(server.writes.last!.keys), Set(wb.map(\.id)))
        XCTAssertEqual(aa.current, beforeA)
        XCTAssertTrue(server.focused.isEmpty)
        XCTAssertEqual(controller.windowChoices.first(where: \.selected)?.id, wa[0].id)
        controller.perform(.strip(.right))
        XCTAssertEqual(
            server.focused, [wa[1].id], "Keyboard focus stays on its display while another display is browsed"
        )
        controller.pause()
        XCTAssertEqual(server.restored, Dictionary(uniqueKeysWithValues: (wa + wb).map { ($0.id, $0.frame) }))
    }
    @MainActor func testTransferKeepsWidthAndPauseRestoresOriginalDisplay() async {
        let defaults = UserDefaults(suiteName: "TapeTests.transfer")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.transfer") }
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let wa = windows(on: a, count: 2)
        let wb = windows(on: b, count: 1)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, b],
            animatorFactory: { ab }, clockFactory: { TestFrameClock() })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        controller.setWidth(2.0 / 3)
        let width = aa.current[wa[0].id]!.width
        controller.perform(.nextDisplay)
        XCTAssertEqual(controller.displayChoices.map(\.windowCount), [1, 2])
        XCTAssertEqual(ab.current[wa[0].id]!.width, width)
        XCTAssertTrue(b.geometry.frame.contains(ab.current[wa[0].id]!))
        XCTAssertEqual(controller.windowChoices.first(where: \.selected)?.id, wa[0].id)
        controller.pause()
        XCTAssertEqual(server.restored[wa[0].id], wa[0].frame)
    }
    @MainActor func testDisableRestoreReenableAndPauseLeaveExcludedDisplayAlone() async {
        let defaults = UserDefaults(suiteName: "TapeTests.disabled")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.disabled") }
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let wa = windows(on: a)
        let wb = windows(on: b)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, b],
            animatorFactory: { ab }, clockFactory: { TestFrameClock() })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        controller.setDisplayEnabled("b", false)
        await pauseForScan()
        XCTAssertEqual(controller.managedCount, 3)
        XCTAssertTrue(server.writes.contains { $0[wb[0].id] == wb[0].frame })
        let writes = server.writes.count
        controller.scroll(by: 100, at: CGPoint(x: 1800, y: 100))
        XCTAssertEqual(server.writes.count, writes)
        controller.pause()
        XCTAssertTrue(wb.allSatisfy { server.restored[$0.id] == nil })
        controller.setDisplayEnabled("b", true)
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: observed(wa + wb, server: server), focus: wa[0].id)
        XCTAssertEqual(controller.displayChoices.map(\.windowCount), [3, 3])
        XCTAssertEqual(TapeSettings(defaults: defaults).disabledDisplays, [])
        controller.pause()
    }
    @MainActor func testUnplugPreservesWindowsWidthsAndReachableRestoration() async {
        let defaults = UserDefaults(suiteName: "TapeTests.unplug")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.unplug") }
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let wa = windows(on: a)
        let wb = windows(on: b)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, b],
            animatorFactory: { ab }, clockFactory: { TestFrameClock() })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        controller.chooseWindow(wb[0].id)
        controller.setWidth(2.0 / 3)
        let oldWidth = ab.current[wb[0].id]!.width
        let cancellationCount = server.cancellations
        controller.updateDisplays([a])
        await pauseForScan()
        XCTAssertGreaterThan(
            server.cancellations, cancellationCount, "Obsolete queued geometry must be discarded on unplug")
        completeLatest(server, windows: observed(wa + wb, server: server), focus: wb[0].id)
        XCTAssertEqual(controller.managedCount, 6)
        XCTAssertEqual(aa.current[wb[0].id]!.width, oldWidth)
        XCTAssertTrue(aa.current.values.allSatisfy { a.geometry.frame.intersection($0).width >= 5.99 })
        controller.pause()
        XCTAssertEqual(server.restored.count, 6)
        XCTAssertTrue(server.restored.values.allSatisfy { a.geometry.visibleFrame.contains($0) })
    }
    @MainActor func testRearrangingDisplaysRestoresLocalWindowPositions() async {
        let defaults = UserDefaults(suiteName: "TapeTests.rearrange")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.rearrange") }
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let wa = windows(on: a, count: 1)
        let wb = windows(on: b, count: 1)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, b],
            animatorFactory: { ab }, clockFactory: { TestFrameClock() })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        let moved = TapeDisplay(
            id: "b", name: "External",
            geometry: ScreenGeometry(
                frame: CGRect(x: -1600, y: 0, width: 1600, height: 1000),
                visibleFrame: CGRect(x: -1600, y: 30, width: 1600, height: 900)))
        controller.updateDisplays([a, moved])
        await pauseForScan()
        let shifted = WindowSnapshot(
            id: wb[0].id, frame: wb[0].frame.offsetBy(dx: -3200, dy: 0), processID: 0, isTileable: true,
            bundleIdentifier: "fixture")
        completeLatest(server, windows: wa + [shifted], focus: wa[0].id)
        controller.pause()
        XCTAssertEqual(
            server.restored[wb[0].id], shifted.frame,
            "Restore the original local position on the same physical display")
        XCTAssertEqual(server.restored[wa[0].id], wa[0].frame)
    }
    @MainActor func testManualMoveBetweenDisplaysKeepsTheWindowPreset() async {
        let defaults = UserDefaults(suiteName: "TapeTests.dragdisplay")!
        defer { defaults.removePersistentDomain(forName: "TapeTests.dragdisplay") }
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let wa = windows(on: a)
        let wb = windows(on: b)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, b],
            animatorFactory: { ab }, clockFactory: { TestFrameClock() })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        controller.setWidth(0.75)
        let width = aa.current[wa[0].id]!.width
        await pauseForScan()
        let next = observed(wa + wb, server: server).map { window -> WindowSnapshot in
            if window.id != wa[0].id { return window }
            return WindowSnapshot(
                id: window.id, frame: CGRect(x: 1800, y: 50, width: width, height: 700), processID: 0,
                isTileable: true, bundleIdentifier: "fixture")
        }
        completeLatest(server, windows: next, focus: wa[0].id)
        XCTAssertEqual(controller.displayChoices.map(\.windowCount), [2, 4])
        XCTAssertEqual(ab.current[wa[0].id]!.width, width)
        controller.pause()
    }
}
