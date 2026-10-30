import XCTest
@testable import BatteryCore

/// 系统只接受它列出的几档。要的值不在里面，就选最近的一档，平手选低的。
final class LimitRoundingTests: XCTestCase {
    private let native = [80, 85, 90, 95, 100]

    func testAcceptedValueIsKept() {
        XCTAssertEqual(LimitRounding.nearestAccepted(85, choices: native), 85)
    }

    func testCustomValueRoundsToNearestStep() {
        XCTAssertEqual(LimitRounding.nearestAccepted(83, choices: native), 85)
        XCTAssertEqual(LimitRounding.nearestAccepted(81, choices: native), 80)
        XCTAssertEqual(LimitRounding.nearestAccepted(97, choices: native), 95)
    }

    /// 85 正好离 80 和 90 一样远，选低的 80。
    func testTieGoesToTheLowerStep() {
        XCTAssertEqual(LimitRounding.nearestAccepted(85, choices: [80, 90]), 80)
    }

    func testBelowTheLowestStepGoesToTheLowest() {
        XCTAssertEqual(LimitRounding.nearestAccepted(50, choices: native), 80)
    }

    /// 系统没列出任何档位（旧系统、或者读不到）：原样返回，由帮手去管。
    func testNoChoicesKeepsTheValue() {
        XCTAssertEqual(LimitRounding.nearestAccepted(83, choices: []), 83)
    }
}
