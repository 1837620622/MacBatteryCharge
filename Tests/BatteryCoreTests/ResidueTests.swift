import XCTest
@testable import BatteryCore

/// 换版本留下的东西：没换上去的新版本马上删；旧版本的备份要等新版本正常跑起来（版本号更高）以后再删，
/// 出问题时它还能用来退回去。别的名字一概不碰。
final class ResidueTests: XCTestCase {
    func testIncompleteNewCopyIsAlwaysRemoved() {
        let names = [UpdateResidue.incomingName, "MacBatteryCharge.app"]
        XCTAssertEqual(UpdateResidue.removable(in: names, runningVersion: "3.1.2", backupVersion: nil),
                       [UpdateResidue.incomingName])
    }

    func testBackupIsKeptWhileOldVersionIsStillTheRunningOne() {
        let names = [UpdateResidue.previousName]
        XCTAssertEqual(UpdateResidue.removable(in: names, runningVersion: "3.1.1", backupVersion: "3.1.1"), [])
        XCTAssertEqual(UpdateResidue.removable(in: names, runningVersion: "3.1.1", backupVersion: "3.1.2"), [])
    }

    func testBackupIsRemovedOnceNewerVersionIsRunning() {
        let names = [UpdateResidue.previousName]
        XCTAssertEqual(UpdateResidue.removable(in: names, runningVersion: "3.1.2", backupVersion: "3.1.1"),
                       [UpdateResidue.previousName])
    }

    func testBackupWithUnreadableVersionIsRemoved() {
        XCTAssertEqual(UpdateResidue.removable(in: [UpdateResidue.previousName], runningVersion: "3.1.2", backupVersion: nil),
                       [UpdateResidue.previousName])
    }

    func testUnrelatedNamesAreNeverTouched() {
        let names = ["MacBatteryCharge.app", "Safari.app", ".DS_Store", "MacBatteryCharge-previous.app"]
        XCTAssertEqual(UpdateResidue.removable(in: names, runningVersion: "3.1.2", backupVersion: "3.1.1"), [])
    }
}
