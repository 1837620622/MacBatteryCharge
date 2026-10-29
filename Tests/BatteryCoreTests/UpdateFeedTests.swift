import XCTest
@testable import BatteryCore

/// 用 GitHub 上 v3.1.1 的真实返回（字段裁剪过）检查更新用到的解析、选包和版本比较。
final class UpdateFeedTests: XCTestCase {
    func testRealReleaseFeedPicksTheMatchingPackage() throws {
        let base = "https://github.com/1837620622/MacFullBar/releases/download/v3.1.1/"
        let json = """
        {"tag_name": "v3.1.1", "html_url": "https://github.com/1837620622/MacFullBar/releases/tag/v3.1.1", "body": "修好了",
         "assets": [
           {"name": "MacBatteryCharge-3.1.1-arm64.dmg", "browser_download_url": "\(base)MacBatteryCharge-3.1.1-arm64.dmg", "size": 1887529, "digest": "sha256:8e7f3fb2bfd522362aad4fcbc959af4c7f5af7ba77900331e4e797559fee23c0"},
           {"name": "MacBatteryCharge-3.1.1-arm64.pkg", "browser_download_url": "\(base)MacBatteryCharge-3.1.1-arm64.pkg", "size": 1766777, "digest": "sha256:614c53447834b30fe1162ce229b5b2b6f91dc02093b42b837ac7f0f481f492a3"},
           {"name": "MacBatteryCharge-3.1.1-intel.dmg", "browser_download_url": "\(base)MacBatteryCharge-3.1.1-intel.dmg", "size": 1912040, "digest": "sha256:dec7bc252b28ee05aa4fdf31a2c1ed4eda36427184c57290ad16a89d37c90d23"},
           {"name": "MacBatteryCharge-3.1.1-intel.pkg", "browser_download_url": "\(base)MacBatteryCharge-3.1.1-intel.pkg", "size": 1791751, "digest": "sha256:5f9905f17216562b6d24cfd0a5bef9b4046a234f3aea5a8340a4c0c412658a74"}
         ]}
        """
        let release = try XCTUnwrap(ReleaseInfo.parse(Data(json.utf8)))
        XCTAssertEqual(release.version, "3.1.1")
        let arm = try XCTUnwrap(release.package(arm64: true))
        XCTAssertEqual(arm.name, "MacBatteryCharge-3.1.1-arm64.pkg")
        XCTAssertEqual(arm.size, 1766777)
        XCTAssertEqual(arm.sha256, "614c53447834b30fe1162ce229b5b2b6f91dc02093b42b837ac7f0f481f492a3")
        XCTAssertEqual(release.package(arm64: false)?.name, "MacBatteryCharge-3.1.1-intel.pkg")
        XCTAssertTrue(AppVersion.isNewer(release.version, than: "3.1.0"), "3.1.0 装着的时候要提示 3.1.1")
        XCTAssertFalse(AppVersion.isNewer(release.version, than: "3.1.1"), "已经是最新版就不提示")
    }
}
