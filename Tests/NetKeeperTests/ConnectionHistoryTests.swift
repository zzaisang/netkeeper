@testable import NetKeeper
import XCTest

final class ConnectionHistoryTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 60 * 1_000_000)

    func testWorstStateInMinuteWins() {
        var history = ConnectionHistory()
        history.record(.wifi, at: start, elapsed: 5, switched: false)
        history.record(.offline, at: start + 5, elapsed: 5, switched: false)
        history.record(.wifi, at: start + 10, elapsed: 5, switched: true)
        XCTAssertEqual(history.slots(now: start + 10).last, .offline)
        XCTAssertEqual(history.downSeconds(now: start + 10), 5)
        XCTAssertEqual(history.switches(now: start + 10), 1)
    }

    func testOnlyLastSixtyMinutesKept() {
        var history = ConnectionHistory()
        history.record(.offline, at: start, elapsed: 5, switched: true)
        history.record(.wifi, at: start + 60 * 60, elapsed: 5, switched: false)
        let slots = history.slots(now: start + 60 * 60)
        XCTAssertEqual(slots.count, 60)
        XCTAssertFalse(slots.contains(.offline))
        XCTAssertEqual(history.switches(now: start + 60 * 60), 0)
        XCTAssertEqual(slots.compactMap { $0 }.count, 1)
    }
}
