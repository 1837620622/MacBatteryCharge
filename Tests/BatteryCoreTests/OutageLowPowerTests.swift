import XCTest
@testable import BatteryCore

/// 停电时的低电量模式：默认不开，勾上「停电时保持低电量」才在停电时开，来电后关。
final class OutageLowPowerTests: XCTestCase {
    /// 停电中，用户勾了：开。
    func testCutWithKeepTurnsOn() {
        XCTAssertEqual(Outage.lowPowerWanted(cutNow: true, keep: true, wereOn: false), true)
        XCTAssertEqual(Outage.lowPowerWanted(cutNow: true, keep: true, wereOn: true), true)
    }

    /// 停电中，没勾：不碰低电量。默认就是这样，停电时照常充电。
    func testCutWithoutKeepLeavesItAlone() {
        XCTAssertNil(Outage.lowPowerWanted(cutNow: true, keep: false, wereOn: false))
    }

    /// 停电中，没勾，但是之前是我们开的（比如停电中途取消了勾）：关掉。
    func testCutWithoutKeepTurnsOffWhatWeTurnedOn() {
        XCTAssertEqual(Outage.lowPowerWanted(cutNow: true, keep: false, wereOn: true), false)
    }

    /// 来电了：只关掉自己开过的，没开过就不动。
    func testPowerBackTurnsOffOnlyWhatWeTurnedOn() {
        XCTAssertEqual(Outage.lowPowerWanted(cutNow: false, keep: true, wereOn: true), false)
        XCTAssertEqual(Outage.lowPowerWanted(cutNow: false, keep: false, wereOn: true), false)
        XCTAssertNil(Outage.lowPowerWanted(cutNow: false, keep: true, wereOn: false))
        XCTAssertNil(Outage.lowPowerWanted(cutNow: false, keep: false, wereOn: false))
    }

    /// 新装和老配置都是不开。
    func testDefaultIsOff() throws {
        XCTAssertFalse(AppSettings().outageLowPower)
        let old = try XCTUnwrap(AppSettings.decode(Data(#"{"outageEnabled":true}"#.utf8)))
        XCTAssertTrue(old.outageEnabled)
        XCTAssertFalse(old.outageLowPower, "老配置没有这一项，停电时照常充电，不偷偷开低电量")
    }

    /// 勾上以后存下来，再读回来还是勾着。
    func testKeepRoundTrips() throws {
        var settings = AppSettings()
        settings.outageLowPower = true
        let decoded = try XCTUnwrap(AppSettings.decode(settings.encoded()))
        XCTAssertTrue(decoded.outageLowPower)
    }
}
