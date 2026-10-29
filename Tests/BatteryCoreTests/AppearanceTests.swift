import XCTest
@testable import BatteryCore

final class AppearanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        pinChineseUI()
    }

    func testLookDefaultsAndRoundTrip() throws {
        var settings = AppSettings()
        XCTAssertEqual(settings.look, .frosted)
        XCTAssertEqual(settings.transparency, 0.25, accuracy: 0.0001)
        settings.look = .glass
        settings.transparency = 0.4
        let decoded = try XCTUnwrap(AppSettings.decode(settings.encoded()))
        XCTAssertEqual(decoded.look, .glass)
        XCTAssertEqual(decoded.transparency, 0.4, accuracy: 0.0001)
    }

    func testLookLenientDecoding() throws {
        // 旧文件没有这两项，或者写了不认识的值：用默认，不丢别的设置。
        let old = try XCTUnwrap(AppSettings.decode(Data(#"{"intervals":[],"guideSeen":true}"#.utf8)))
        XCTAssertEqual(old.look, .frosted)
        XCTAssertTrue(old.guideSeen)
        let odd = try XCTUnwrap(AppSettings.decode(Data(#"{"look":"neon","transparency":9}"#.utf8)))
        XCTAssertEqual(odd.look, .frosted)
        XCTAssertEqual(odd.transparency, AppSettings.transparencyRange.upperBound, accuracy: 0.0001, "透明度最多 0.7")
        let negative = try XCTUnwrap(AppSettings.decode(Data(#"{"transparency":-3}"#.utf8)))
        XCTAssertEqual(negative.transparency, 0, accuracy: 0.0001)
    }

    func testLookTitles() {
        XCTAssertEqual(WindowLook.allCases.map(\.title), ["纯色", "磨砂", "玻璃"])
    }

    func testAuthor() {
        XCTAssertEqual(AppInfo.author, "传康Kk")
        XCTAssertEqual(AppInfo.authorPage.absoluteString, "https://github.com/1837620622")
        XCTAssertEqual(AppInfo.homepage.absoluteString, "https://github.com/1837620622/MacFullBar")
        XCTAssertTrue(AppInfo.copyright.contains(AppInfo.author))
    }

    func testAdviceTopPutsWarningsFirst() {
        let items = [
            AdviceItem(.good, "a", "好 1"),
            AdviceItem(.info, "b", "提示 1"),
            AdviceItem(.warn, "c", "警告 1"),
            AdviceItem(.good, "d", "好 2"),
            AdviceItem(.warn, "e", "警告 2"),
        ]
        XCTAssertEqual(Advice.top(items).map(\.text), ["警告 1", "警告 2", "提示 1"])
        XCTAssertEqual(Advice.top(items, count: 10).count, 5)
        XCTAssertTrue(Advice.top([]).isEmpty)
    }

    func testAdviceTextsStayShort() {
        var battery = BatterySnapshot()
        battery.present = true
        battery.percent = 95
        battery.externalConnected = true
        battery.milliamps = -600
        battery.adapterWatts = 20
        battery.temperatureRaw = 4300
        battery.cycles = 900
        battery.designCycles = 1000
        battery.designCapacity = 6000
        battery.nominalCapacity = 4500
        battery.thermallyLimited = true
        let memory = MemorySnapshot(totalBytes: 8 << 30, pageSize: 4096, free: 10, active: 100_000, inactive: 10,
                                    wired: 100_000, compressed: 50_000, speculative: 0, pressure: 4)
        for discharging in [false, true] {
            let items = Advice.items(battery: battery, memory: memory, limit: 80, heatActive: true, discharging: discharging)
            XCTAssertFalse(items.isEmpty)
            for item in items {
                XCTAssertLessThanOrEqual(item.text.count, 22, "太长：\(item.text)")
            }
        }
    }
}
