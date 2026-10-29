import XCTest
@testable import BatteryCore

final class BatterySnapshotTests: XCTestCase {
    /// 系统还在算的时候给 65535，不能当成「一千多个小时」显示出来。
    func testSystemPlaceholderTimeIsNotShown() {
        XCTAssertNil(BatterySnapshot.plausibleMinutes(65535))
        XCTAssertNil(BatterySnapshot.plausibleMinutes(NSNumber(value: 65535)))
        XCTAssertNil(BatterySnapshot.plausibleMinutes(0))
        XCTAssertNil(BatterySnapshot.plausibleMinutes(nil))
    }

    func testReasonableTimesAreKept() {
        XCTAssertEqual(BatterySnapshot.plausibleMinutes(95), 95)
        XCTAssertEqual(BatterySnapshot.plausibleMinutes(NSNumber(value: 1439)), 1439)
        XCTAssertNil(BatterySnapshot.plausibleMinutes(1440), "超过一天的估计不信")
    }
}
