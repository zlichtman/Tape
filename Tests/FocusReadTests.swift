import XCTest
@testable import TapeRuntime

final class FocusReadTests: XCTestCase {
    func testNewestNotificationSupersedesQueuedAndInFlightReads() {
        var gate = FocusReadGate()
        let old = gate.request(command: 1)
        let newest = gate.request(command: 1)
        XCTAssertFalse(gate.accepts(old, command: 1))
        XCTAssertTrue(gate.accepts(newest, command: 1))
    }
    func testKeyboardCommandInvalidatesEarlierRead() {
        var gate = FocusReadGate()
        let read = gate.request(command: 1)
        XCTAssertFalse(gate.accepts(read, command: 2))
        let afterCommand = gate.request(command: 2)
        XCTAssertTrue(gate.accepts(afterCommand, command: 2))
        XCTAssertFalse(gate.accepts(afterCommand, command: 3))
    }
}
