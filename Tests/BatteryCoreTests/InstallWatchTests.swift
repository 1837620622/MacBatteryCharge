import XCTest
@testable import BatteryCore

/// 新版本装进「应用程序」以后，要等拷贝完了才重新打开：连续两次看到同一份指纹才算装完。
final class InstallWatchTests: XCTestCase {
    func testNothingInstalledNeverFires() {
        var watch = InstallWatch()
        for _ in 0..<5 { XCTAssertFalse(watch.observe(nil)) }
    }

    func testFiresOnlyWhenTheSameFingerprintIsSeenTwice() {
        var watch = InstallWatch()
        XCTAssertFalse(watch.observe("3.2.4|1000|1.0"))
        XCTAssertTrue(watch.observe("3.2.4|1000|1.0"))
    }

    func testFingerprintStillChangingMeansStillCopying() {
        var watch = InstallWatch()
        XCTAssertFalse(watch.observe("3.2.4|1000|1.0"))
        XCTAssertFalse(watch.observe("3.2.4|4000|2.0"))
        XCTAssertFalse(watch.observe("3.2.4|9000|3.0"))
        XCTAssertTrue(watch.observe("3.2.4|9000|3.0"))
    }

    func testInstallGoingAwayResetsTheCount() {
        var watch = InstallWatch()
        XCTAssertFalse(watch.observe("3.2.4|1000|1.0"))
        XCTAssertFalse(watch.observe(nil))
        XCTAssertFalse(watch.observe("3.2.4|1000|1.0"))
        XCTAssertTrue(watch.observe("3.2.4|1000|1.0"))
    }
}
