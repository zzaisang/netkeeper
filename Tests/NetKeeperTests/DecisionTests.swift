@testable import NetKeeper
import XCTest

final class DecisionTests: XCTestCase {
    let priority = ["Home", "Office", "iPhone"]

    func testHigherPriorityAppearsWhileOnHotspot() {
        XCTAssertEqual(decide(current: "iPhone", online: true, visible: ["Home", "iPhone"], priority: priority, cooling: []), .connect("Home"))
    }

    func testStayOnBestWhenOnline() {
        XCTAssertEqual(decide(current: "Home", online: true, visible: ["Home", "Office"], priority: priority, cooling: []), .stay)
    }

    func testFallbackToHotspotWhenWifiDead() {
        XCTAssertEqual(decide(current: "Home", online: false, visible: ["Home", "iPhone"], priority: priority, cooling: ["Home"]), .connect("iPhone"))
    }

    func testOnlineHigherNetworkNotDroppedWhenMissingFromScan() {
        XCTAssertEqual(decide(current: "Home", online: true, visible: ["Office"], priority: priority, cooling: []), .stay)
    }

    func testUnknownNetworkReplacedByPreferred() {
        XCTAssertEqual(decide(current: "Cafe", online: true, visible: ["Cafe", "Office"], priority: priority, cooling: []), .connect("Office"))
    }

    func testNothingUsable() {
        XCTAssertEqual(decide(current: nil, online: false, visible: ["Cafe"], priority: priority, cooling: []), .stay)
    }
}
