import XCTest
import AppKit
@testable import TapeEngine
@testable import TapeRuntime

final class TestFrameClock: FrameClocking {
    var tick: (() -> Void)?
    @discardableResult func start(screen: NSScreen?, tick: @escaping () -> Void) -> Bool { self.tick = tick; return true }
    func stop() { tick = nil }
}

final class ScrollingTests: XCTestCase {
    func testGestureKeepsMomentumAfterReleasingModifiers() {
        var g = ScrollGesture()
        XCTAssertTrue(g.consume(x: 20, y: 1, precise: true, modifiers: true, eligible: true, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 1))
        XCTAssertTrue(g.consume(x: 8, y: 1, precise: true, modifiers: false, eligible: true, begins: false, momentum: true, cancelled: false, finishesMomentum: false, now: 1.5))
        XCTAssertTrue(g.consume(x: 0, y: 0, precise: true, modifiers: false, eligible: true, begins: false, momentum: true, cancelled: false, finishesMomentum: true, now: 1.6))
        XCTAssertFalse(g.consume(x: 12, y: 1, precise: true, modifiers: false, eligible: true, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 1.7))
    }
    func testOrdinaryVerticalAndMouseWheelScrollingPassThrough() {
        for (x, y, precise, mods) in [(10.0, 0.0, true, false), (1, 20, true, true), (10, 0, false, true)] {
            var g = ScrollGesture()
            XCTAssertFalse(g.consume(x: x, y: y, precise: precise, modifiers: mods, eligible: true, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 1))
        }
    }
    func testCannotCaptureMiddleOfAnOrdinaryGestureOrOrphanMomentum() {
        var g = ScrollGesture()
        XCTAssertFalse(g.consume(x: 0, y: 10, precise: true, modifiers: false, eligible: true, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 1))
        XCTAssertFalse(g.consume(x: 20, y: 0, precise: true, modifiers: true, eligible: true, begins: false, momentum: false, cancelled: false, finishesMomentum: false, now: 1.1))
        g.reset()
        XCTAssertFalse(g.consume(x: 20, y: 0, precise: true, modifiers: true, eligible: true, begins: false, momentum: true, cancelled: false, finishesMomentum: false, now: 2))
    }
    func testCancellationAndIneligibleDisplayReleaseGesture() {
        var g = ScrollGesture()
        XCTAssertTrue(g.consume(x: 20, y: 0, precise: true, modifiers: true, eligible: true, begins: true, momentum: false, cancelled: true, finishesMomentum: false, now: 1))
        XCTAssertFalse(g.consume(x: 10, y: 0, precise: true, modifiers: false, eligible: true, begins: false, momentum: true, cancelled: false, finishesMomentum: false, now: 1.1))
        XCTAssertFalse(g.consume(x: 20, y: 0, precise: true, modifiers: true, eligible: false, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 2))
    }
    func testScrollBoundsPreserveFocusAndWidths() {
        var strip = Strip()
        for _ in 0..<8 { strip.insert(WindowID(), foreground: false) }
        strip.focusedWindow = strip.columns[0].windows[0]
        let focus = strip.focusedWindow, columns = strip.columns
        let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900))
        let options = LayoutOptions()
        strip.scrollOffset = Layout.scrolledOffset(for: strip, by: 100_000, screen: geometry, options: options)
        XCTAssertGreaterThan(strip.scrollOffset, 0)
        let last = Layout.columnRects(for: strip, screen: geometry, options: options).last!
        XCTAssertEqual(last.maxX, Layout.contentRect(screen: geometry, options: options).maxX, accuracy: 0.001)
        strip.scrollOffset = Layout.scrolledOffset(for: strip, by: -100_000, screen: geometry, options: options)
        XCTAssertEqual(strip.scrollOffset, 0)
        XCTAssertEqual(strip.focusedWindow, focus)
        XCTAssertEqual(strip.columns, columns)
        XCTAssertEqual(Layout.scrolledOffset(for: strip, by: .nan, screen: geometry, options: options), 0)
    }
    @MainActor func testDisplayTicksDoNotSkipHighRefreshFramesAndRetargetDoesNotRestartFullDuration() {
        let clock = TestFrameClock()
        var now = 0.0
        let animator = Animator(clock: clock, now: { now }, systemReduceMotion: { false })
        let id = WindowID(), origin = CGRect(x: 0, y: 30, width: 300, height: 600)
        let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900))
        var writes = 0, completed = 0
        animator.animate(to: [id: origin.offsetBy(dx: 400, dy: 0)], from: [id: origin], screen: nil, geometry: screen, reduceMotion: false, write: { _ in writes += 1 }, completion: { completed += 1 })
        // The system preference is injected, so every pacing assertion runs.
        if animator.isAnimating {
            let count = writes
            for i in 1...4 { now = Double(i) / 120; clock.tick?() }
            XCTAssertEqual(writes, count + 4)
            now = 0.04
            animator.animate(to: [id: origin.offsetBy(dx: 800, dy: 0)], from: [:], screen: nil, geometry: screen, reduceMotion: false, write: { _ in writes += 1 }, completion: { completed += 1 })
            now = 0.141; clock.tick?()
            XCTAssertFalse(animator.isAnimating)
            XCTAssertEqual(completed, 1)
            XCTAssertEqual(animator.current[id], origin.offsetBy(dx: 800, dy: 0))
        }
    }
    func testSlowAppDoesNotBlockOtherAppAndPendingFramesCoalesce() {
        let a = WindowID(), b = WindowID()
        let started = expectation(description: "slow app started"), fast = expectation(description: "other app wrote"), latest = expectation(description: "latest pending frame wrote")
        let release = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var values: [Double] = []
        let queue = FrameWriteQueue { job in
            if job.id == a {
                lock.lock(); values.append(job.frame.minX); lock.unlock()
                if job.frame.minX == 0 { started.fulfill(); _ = release.wait(timeout: .now() + 2) }
                if job.frame.minX == 100 { latest.fulfill() }
            } else { fast.fulfill() }
        }
        func job(_ id: WindowID, _ x: Double) -> FrameWrite { FrameWrite(id: id, frame: CGRect(x: x, y: 0, width: 300, height: 500), generation: 0) }
        queue.enqueue([(1, job(a, 0))])
        wait(for: [started], timeout: 1)
        for i in 1...100 { queue.enqueue([(1, job(a, Double(i)))]) }
        queue.enqueue([(2, job(b, 5))])
        wait(for: [fast], timeout: 1)
        release.signal()
        wait(for: [latest], timeout: 1)
        lock.lock(); let observed = values; lock.unlock()
        XCTAssertEqual(observed, [0, 100], "Intermediate queued frames must not replay")
    }
    func testReconciliationWaitsForInFlightAndNewestQueuedWrite() {
        let started = expectation(description: "first started"), settled = expectation(description: "all writes settled")
        let release = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var values: [Double] = []
        let queue = FrameWriteQueue { job in
            if job.frame.minX == 0 { started.fulfill(); _ = release.wait(timeout: .now() + 2) }
            lock.lock(); values.append(job.frame.minX); lock.unlock()
        }
        let id = WindowID(), rect = CGRect(x: 0, y: 0, width: 300, height: 500)
        queue.enqueue([(1, FrameWrite(id: id, frame: rect, generation: 0))])
        wait(for: [started], timeout: 1)
        queue.enqueue([(1, FrameWrite(id: id, frame: rect.offsetBy(dx: 50, dy: 0), generation: 0))])
        queue.whenIdle {
            lock.lock(); let written = values; lock.unlock()
            XCTAssertEqual(written, [0, 50])
            settled.fulfill()
        }
        release.signal()
        wait(for: [settled], timeout: 1)
    }
    @MainActor func testUnavailableDisplayClockCompletesAnimation() {
        final class FailedClock: FrameClocking {
            func start(screen: NSScreen?, tick: @escaping () -> Void) -> Bool { false }
            func stop() {}
        }
        let animator = Animator(clock: FailedClock(), now: { 0 }, systemReduceMotion: { false })
        let id = WindowID(), rect = CGRect(x: 10, y: 30, width: 300, height: 500)
        let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900))
        var completed = false
        animator.animate(to: [id: rect], from: [id: rect.offsetBy(dx: 100, dy: 0)], screen: nil, geometry: screen, reduceMotion: false, write: { _ in }, completion: { completed = true })
        XCTAssertTrue(completed)
        XCTAssertFalse(animator.isAnimating)
        XCTAssertEqual(animator.current[id], rect)
    }
    func testCancellingQueueDropsWaitingFrames() {
        let first = expectation(description: "first frame started"), done = expectation(description: "first frame finished")
        let release = DispatchSemaphore(value: 0), lock = NSLock()
        var writes = 0
        let queue = FrameWriteQueue { _ in
            lock.lock(); writes += 1; lock.unlock()
            first.fulfill(); _ = release.wait(timeout: .now() + 2); done.fulfill()
        }
        let id = WindowID(), rect = CGRect(x: 0, y: 0, width: 300, height: 500)
        queue.enqueue([(1, FrameWrite(id: id, frame: rect, generation: 0))])
        wait(for: [first], timeout: 1)
        queue.enqueue([(1, FrameWrite(id: id, frame: rect.offsetBy(dx: 10, dy: 0), generation: 0))])
        queue.cancelPending(); release.signal()
        wait(for: [done], timeout: 1)
        lock.lock(); let count = writes; lock.unlock()
        XCTAssertEqual(count, 1)
    }
}
