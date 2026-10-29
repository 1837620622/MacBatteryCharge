import XCTest
@testable import BatteryCore

private func at(_ hour: Int, _ minute: Int) -> Int { hour * 60 + minute }

private func interval(_ start: String, _ end: String, _ limit: Int, _ low: LowPowerChoice = .off) -> Interval {
    Interval(start: ClockTime(text: start)!, end: ClockTime(text: end)!, limit: limit, lowPower: low)
}

private func compiled(_ items: [Interval]) -> Schedule {
    guard case .success(let schedule) = Schedule.compile(items) else {
        XCTFail("时间表应能通过")
        return .empty
    }
    return schedule
}

final class ScheduleTests: XCTestCase {
    func testDefaults() {
        let schedule = compiled(Schedule.makeDefaults())
        XCTAssertEqual(schedule.limit(at: at(5, 59)), 100, "05:59 应为 100")
        XCTAssertEqual(schedule.limit(at: at(6, 0)), 80, "06:00 应为 80")
        XCTAssertEqual(schedule.limit(at: at(20, 59)), 80, "20:59 应为 80")
        XCTAssertEqual(schedule.limit(at: at(21, 0)), 100, "21:00 应为 100")
        XCTAssertEqual(schedule.limit(at: at(23, 30)), 100, "23:30 应为 100")
        XCTAssertEqual(schedule.lowPower(at: at(10, 0)), .off, "白天默认不用低电量")
        XCTAssertEqual(schedule.lowPower(at: at(22, 0)), .battery, "晚间默认仅电池开低电量")
        XCTAssertEqual(schedule.lowPower(at: at(5, 0)), .battery, "清晨仍在晚间这一段")
        XCTAssertFalse((0..<1440).contains { schedule.isGap(at: $0) }, "默认时间段应盖住一整天")
        XCTAssertEqual(schedule.blocks.map(\.limit), [100, 80, 100])
    }

    func testRejects() {
        XCTAssertEqual(Schedule.compile([interval("06:00", "12:00", 80), interval("11:00", "13:00", 90)]).failure, .overlap(1, 2))
        XCTAssertNil(ClockTime(text: "25:00"), "非法时间应拒绝")
        XCTAssertNil(ClockTime(text: "6:0:0"))
        XCTAssertNil(ClockTime(text: "a6:00"))
        XCTAssertEqual(ClockTime(text: "6:05")?.text, "06:05")
        XCTAssertEqual(Schedule.compile([interval("06:00", "07:00", 70)]).failure, .badLimit(1), "70 应拒绝")
        XCTAssertEqual(Schedule.compile([interval("06:00", "06:00", 80)]).failure, .sameStartEnd(1), "零长度应拒绝")
        let many = (0..<13).map { interval(String(format: "%02d:00", $0), String(format: "%02d:30", $0), 80) }
        XCTAssertEqual(Schedule.compile(many).failure, .tooMany, "最多 12 段")
        XCTAssertEqual(ScheduleError.overlap(1, 2).message, "第 1 段和第 2 段有重叠")
    }

    func testGapAndEmpty() {
        let lone = compiled([interval("06:00", "21:00", 80)])
        XCTAssertEqual(lone.limit(at: at(22, 0)), 100, "空档应按 100")
        XCTAssertTrue(lone.isGap(at: at(22, 0)))
        let empty = compiled([])
        XCTAssertEqual(empty.limit(at: at(12, 0)), 100)
        XCTAssertNil(empty.nextChange(after: 0))
    }

    func testNextChange() {
        let schedule = compiled(Schedule.makeDefaults())
        let change = schedule.nextChange(after: at(20, 0))
        XCTAssertEqual(change?.at.text, "21:00")
        XCTAssertEqual(change?.limit, 100)
        XCTAssertEqual(change?.minutesAhead, 60)
        XCTAssertEqual(schedule.minutesUntilBoundary(from: at(23, 0)), 7 * 60)
    }

    func testFreeSlot() {
        let slot = Schedule.firstFreeSlot(in: [interval("06:00", "21:00", 80)])
        XCTAssertEqual(slot?.start.text, "21:00")
        XCTAssertEqual(slot?.end.text, "22:00")
        XCTAssertNil(Schedule.firstFreeSlot(in: Schedule.makeDefaults()), "排满了不能再加")
        XCTAssertEqual(Schedule.firstFreeSlot(in: [])?.start.text, "06:00")
        let short = Schedule.firstFreeSlot(in: [interval("06:00", "21:00", 80), interval("21:20", "06:00", 100)])
        XCTAssertEqual(short?.end.text, "21:20", "空档短于一小时就填满它")
    }

    func testWrapAndLength() {
        let night = interval("21:00", "06:00", 100)
        XCTAssertTrue(night.wrapsMidnight)
        XCTAssertEqual(night.length, 9 * 60)
        XCTAssertTrue(night.contains(at(0, 0)))
        XCTAssertFalse(night.contains(at(6, 0)))
        XCTAssertEqual(night.rangeText, "21:00 – 次日 06:00")
    }
}

final class SettingsTests: XCTestCase {
    func testLegacyFile() throws {
        let json = """
        {"guideSeen": true, "launchAtLogin": false, "lowPowerAuto": true,
         "intervals": [{"start": "06:00", "end": "21:00", "limit": 80},
                       {"start": "21:00", "end": "06:00", "limit": 100, "lowPower": "off"},
                       {"start": "bad", "end": "06:00", "limit": 100}]}
        """
        let settings = try XCTUnwrap(AppSettings.decode(Data(json.utf8)))
        XCTAssertTrue(settings.guideSeen)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.intervals.count, 2, "坏的一段丢掉，其余保留")
        XCTAssertEqual(settings.intervals[0].lowPower, .battery, "旧的全局开关迁到每一段")
        XCTAssertEqual(settings.intervals[1].lowPower, .off)
        XCTAssertTrue(settings.deadlineEnabled)
        XCTAssertEqual(settings.deadline.text, "23:30")
    }

    func testEmptyStaysEmpty() throws {
        let settings = try XCTUnwrap(AppSettings.decode(Data(#"{"intervals": []}"#.utf8)))
        XCTAssertTrue(settings.intervals.isEmpty, "删光了不换回默认")
        XCTAssertEqual(try XCTUnwrap(AppSettings.decode(Data("{}".utf8))).intervals.count, 2, "没有这个键才用默认")
    }

    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.deadline = ClockTime(hour: 22, minute: 45)
        settings.lastUpdateCheck = Date(timeIntervalSince1970: 1_700_000_000)
        let back = try XCTUnwrap(AppSettings.decode(try settings.encoded()))
        XCTAssertEqual(back.deadline.text, "22:45")
        XCTAssertEqual(back.lastUpdateCheck, settings.lastUpdateCheck)
        XCTAssertEqual(back.intervals.map(\.rangeText), settings.intervals.map(\.rangeText))
        let text = String(decoding: try settings.encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains("\"lowPower\" : \"battery\""))
        XCTAssertFalse(text.contains("\"id\""), "文件里不存内部编号")
    }
}

final class BatteryTests: XCTestCase {
    let sample: [String: Any] = [
        "CurrentCapacity": 100, "MaxCapacity": 100, "InstantAmperage": 0, "Voltage": 12578,
        "CycleCount": 618, "DesignCycleCount9C": 1000, "DesignCapacity": 5103,
        "NominalChargeCapacity": 4229, "AppleRawMaxCapacity": 4096, "Temperature": 3000,
        "TimeChargingThermallyLimited": 0, "IsCharging": "No", "ExternalConnected": "Yes",
    ]

    func testReadings() {
        let battery = BatterySnapshot(registry: sample, powerSource: nil, adapter: ["Watts": 96])
        XCTAssertTrue(battery.present)
        XCTAssertEqual(battery.health, 83, "健康度按标称容量四舍五入")
        XCTAssertEqual(battery.celsius, 30.0, "温度按百分度换算")
        XCTAssertEqual(battery.percent, 100)
        XCTAssertEqual(battery.cycles, 618)
        XCTAssertEqual(battery.adapterWatts, 96)
        XCTAssertEqual(battery.flow, .plugged, "接通但没有电流")
        XCTAssertEqual(battery.flow.menuWord, "接通")
    }

    func testNegativeAmperageFromUnsigned() {
        var registry = sample
        registry["InstantAmperage"] = UInt64(bitPattern: -1200)
        registry["ExternalConnected"] = false
        let battery = BatterySnapshot(registry: registry, powerSource: nil, adapter: nil)
        XCTAssertEqual(battery.milliamps, -1200, "无符号的负电流要还原")
        XCTAssertEqual(battery.flow, .discharging, "放电不能显示成充电")
        registry["InstantAmperage"] = NSNumber(value: UInt64(bitPattern: -800))
        XCTAssertEqual(BatterySnapshot(registry: registry, powerSource: nil, adapter: nil).milliamps, -800)
        registry["InstantAmperage"] = "18446744073709550416"
        XCTAssertEqual(BatterySnapshot(registry: registry, powerSource: nil, adapter: nil).milliamps, -1200)
        registry["InstantAmperage"] = 9_000_000
        XCTAssertNil(BatterySnapshot(registry: registry, powerSource: nil, adapter: nil).milliamps, "离谱的电流不显示")
    }

    func testIntelPercentFromPowerSource() {
        var registry = sample
        registry["CurrentCapacity"] = 3100
        registry["MaxCapacity"] = 4100
        let ps: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 76, "Max Capacity": 100,
                                 "Is Charging": true, "Power Source State": "AC Power", "Time to Full Charge": 42]
        let battery = BatterySnapshot(registry: registry, powerSource: ps, adapter: nil)
        XCTAssertEqual(battery.percent, 76, "Intel 上用 IOPS 的百分比")
        XCTAssertEqual(battery.minutesToFull, 42)
        XCTAssertEqual(BatterySnapshot(registry: registry, powerSource: nil, adapter: nil).percent, 76, "没有 IOPS 时按 mAh 换算")
    }

    func testFlags() {
        var registry = sample
        registry["IsCharging"] = 0
        XCTAssertEqual(BatterySnapshot(registry: registry, powerSource: nil, adapter: nil).isCharging, false, "IsCharging=0 不是在充电")
        registry["IsCharging"] = true
        let charging = BatterySnapshot(registry: registry, powerSource: nil, adapter: nil)
        XCTAssertEqual(charging.flow.menuWord, "充电")
        XCTAssertEqual(BatterySnapshot().flow.menuWord, "无电池", "没有电池时下排写无电池")
        XCTAssertEqual(BatterySnapshot(registry: nil, powerSource: nil, adapter: nil).flow, .noBattery)
    }

    func testNestedBatteryData() {
        let registry: [String: Any] = ["CurrentCapacity": 50, "MaxCapacity": 100,
                                       "BatteryData": ["DesignCapacity": 5000, "NominalChargeCapacity": 4500]]
        XCTAssertEqual(BatterySnapshot(registry: registry, powerSource: nil, adapter: nil).health, 90)
    }

    func testTemperatureUnits() {
        var battery = BatterySnapshot()
        battery.temperatureRaw = 31
        XCTAssertEqual(battery.celsius, 31)
        battery.temperatureRaw = 99_999
        XCTAssertNil(battery.celsius)
    }
}

final class AdviceTests: XCTestCase {
    func testNoBattery() {
        let items = Advice.items(battery: BatterySnapshot(), memory: MemorySnapshot(), limit: 80, heatActive: false)
        XCTAssertTrue(items.first?.text.contains("没有内置电池") == true, "台式机不要装成有电池")
    }

    func testAboveLimitDoesNotDischarge() {
        var battery = BatterySnapshot()
        battery.present = true
        battery.percent = 95
        battery.externalConnected = true
        battery.milliamps = 0
        battery.temperatureRaw = 3000
        let text = Advice.items(battery: battery, memory: MemorySnapshot(), limit: 80, heatActive: false).map(\.text).joined()
        XCTAssertTrue(text.contains("只停充"), "没放电时只停止充电")
        XCTAssertTrue(text.contains("正常"), "30°C 算正常温度")
        let live = Advice.items(battery: battery, memory: MemorySnapshot(), limit: 80, heatActive: false, discharging: true).map(\.text).joined()
        XCTAssertTrue(live.contains("放电中"))
        XCTAssertFalse(live.contains("只停充"))
    }

    func testWeakCharger() {
        var battery = BatterySnapshot()
        battery.present = true
        battery.percent = 60
        battery.externalConnected = true
        battery.milliamps = -600
        battery.adapterWatts = 20
        let items = Advice.items(battery: battery, memory: MemorySnapshot(), limit: 80, heatActive: false)
        XCTAssertTrue(items.contains { $0.tone == .warn && $0.text.contains("20 W") })
    }

    func testMemory() {
        let memory = MemorySnapshot(totalBytes: 16 << 30, pageSize: 16384, free: 1000, active: 2000, inactive: 500,
                                    wired: 800, compressed: 100, speculative: 50, pressure: 1)
        XCTAssertEqual(memory.totalBytes, 16 << 30, "总内存照传入值")
        XCTAssertEqual(memory.usedBytes, 2900 * 16384, "已用按活跃、联动和压缩估算")
        XCTAssertEqual(memory.pressureText, "正常")
        let tight = MemorySnapshot(totalBytes: 8 << 30, pageSize: 4096, free: 10, active: 100_000, inactive: 10,
                                   wired: 100_000, compressed: 50_000, speculative: 0, pressure: 4)
        var battery = BatterySnapshot()
        battery.present = true
        battery.milliamps = -400
        let text = Advice.items(battery: battery, memory: tight, limit: 80, heatActive: false).map(\.text).joined()
        XCTAssertTrue(text.contains("放电"), "放电且内存紧要一起说")
        XCTAssertEqual(MemorySnapshot.bytesText(512 << 20), "512 MB")
    }
}

final class PlannerTests: XCTestCase {
    func testPolicy() {
        let schedule = compiled(Schedule.makeDefaults())
        XCTAssertEqual(ChargePolicy.decide(schedule: schedule, minute: at(10, 0), topUp: false, deadlineLift: nil, heat: false).limit, 80)
        XCTAssertEqual(ChargePolicy.decide(schedule: schedule, minute: at(10, 0), topUp: true, deadlineLift: nil, heat: false).reason, .topUp)
        XCTAssertEqual(ChargePolicy.decide(schedule: schedule, minute: at(10, 0), topUp: false, deadlineLift: 100, heat: false).reason, .deadline)
        let hot = ChargePolicy.decide(schedule: schedule, minute: at(22, 0), topUp: true, deadlineLift: nil, heat: true)
        XCTAssertEqual(hot.limit, 80, "过热时最高 80")
        XCTAssertEqual(hot.reason, .heat)
        XCTAssertEqual(hot.scheduled, 100)
        XCTAssertEqual(ChargePolicy.decide(schedule: schedule, minute: at(10, 0), topUp: false, deadlineLift: 80, heat: true).reason, .schedule, "已经 80 不算过热压低")
    }

    func testHeatHysteresis() {
        XCTAssertTrue(ChargePolicy.heatActive(previous: false, celsius: 40.5, external: true))
        XCTAssertTrue(ChargePolicy.heatActive(previous: true, celsius: 38.5, external: true), "中间保持")
        XCTAssertFalse(ChargePolicy.heatActive(previous: false, celsius: 38.5, external: true))
        XCTAssertFalse(ChargePolicy.heatActive(previous: true, celsius: 36.9, external: true))
        XCTAssertFalse(ChargePolicy.heatActive(previous: true, celsius: 45, external: false), "拔掉电源就解除")
    }

    func testDefaultScheduleIsEarlyEnough() {
        let schedule = compiled(Schedule.makeDefaults())
        let plan = ChargePlanner.plan(schedule: schedule, minute: at(20, 0), percent: 80,
                                      deadline: ClockTime(hour: 23, minute: 30), rate: nil)
        XCTAssertEqual(plan?.target, 100)
        XCTAssertEqual(plan?.liftNow, false, "21:00 放开来得及")
        XCTAssertEqual(plan?.etaMinutes, 60 + 61, "21:00 起约一小时充满")
        XCTAssertEqual(plan?.reachesInTime, true)
    }

    func testLateScheduleLiftsEarlier() {
        let late = compiled([interval("06:00", "23:00", 80), interval("23:00", "06:00", 100)])
        let deadline = ClockTime(hour: 23, minute: 30)
        let early = ChargePlanner.plan(schedule: late, minute: at(21, 0), percent: 80, deadline: deadline, rate: 0.33)
        XCTAssertEqual(early?.liftNow, false, "21:00 还早")
        let now = ChargePlanner.plan(schedule: late, minute: at(22, 14), percent: 80, deadline: deadline, rate: 0.33)
        XCTAssertEqual(now?.liftNow, true, "61 分钟 + 15 分钟余量，22:14 就要放开")
        XCTAssertNil(ChargePlanner.plan(schedule: late, minute: at(10, 0), percent: 80, deadline: deadline, rate: nil), "离断电太远不算")
        let full = ChargePlanner.plan(schedule: late, minute: at(22, 30), percent: 100, deadline: deadline, rate: nil)
        XCTAssertEqual(full?.liftNow, false)
        XCTAssertEqual(full?.etaMinutes, 0)
    }

    func testLearnedRate() {
        var history = ChargeHistory()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for step in 0...10 {
            history.add(ChargeSample(t: start.addingTimeInterval(Double(step) * 300), p: 80 + step * 2, c: true, x: true, l: 100))
        }
        let rate = try? XCTUnwrap(history.learnedRate())
        XCTAssertEqual(rate ?? 0, 0.4, accuracy: 0.001, "每五分钟 2%")
        var short = ChargeHistory()
        short.add(ChargeSample(t: start, p: 80, c: true, x: true, l: 100))
        short.add(ChargeSample(t: start.addingTimeInterval(300), p: 82, c: true, x: true, l: 100))
        XCTAssertNil(short.learnedRate(), "数据太少不学")
    }

    func testHistoryPruning() {
        var history = ChargeHistory()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        history.add(ChargeSample(t: start, p: 50, c: false, x: false, l: 80))
        history.add(ChargeSample(t: start.addingTimeInterval(60), p: 50, c: false, x: false, l: 80))
        XCTAssertEqual(history.samples.count, 1, "没变化时四分钟一条")
        history.add(ChargeSample(t: start.addingTimeInterval(120), p: 49, c: false, x: false, l: 80))
        XCTAssertEqual(history.samples.count, 2, "电量变了马上记")
        history.add(ChargeSample(t: start.addingTimeInterval(80 * 3600), p: 40, c: false, x: false, l: 80))
        XCTAssertEqual(history.samples.count, 1, "超过 72 小时的丢掉")
        history.addHealth(HealthPoint(day: "2026-10-01", health: 90, cycles: 100))
        history.addHealth(HealthPoint(day: "2026-10-01", health: 89, cycles: 101))
        XCTAssertEqual(history.health.count, 1)
        XCTAssertEqual(history.health.first?.health, 89)
    }
}

final class TextTests: XCTestCase {
    func testVersions() {
        XCTAssertTrue(AppVersion.isNewer("v2.0.1", than: "2.0.0"), "新版本应判断为更新")
        XCTAssertFalse(AppVersion.isNewer("v2.0.0", than: "2.0.0"), "相同版本不是更新")
        XCTAssertFalse(AppVersion.isNewer("v1.9.9", than: "2.0.0"), "旧版本不是更新")
        XCTAssertTrue(AppVersion.isNewer("2.1", than: "2.0.9"), "少一段的版本号也能比")
        XCTAssertFalse(AppVersion.isNewer("beta", than: "2.0.0"), "无法解析的版本不是更新")
        XCTAssertTrue(AppVersion.isNewer("3.0.0", than: "2.1.1"))
        XCTAssertTrue(AppVersion.isNewer("2.10.0", than: "2.9.0"), "按数字比，不按字符串")
    }

    func testRelease() throws {
        let json = """
        {"tag_name": "v3.0.1", "html_url": "https://github.com/x/y/releases/tag/v3.0.1", "body": " 修好了 \\n",
         "assets": [
           {"name": "MacBatteryCharge-3.0.1-arm64.dmg", "browser_download_url": "https://e.com/a.dmg", "size": 10},
           {"name": "MacBatteryCharge-3.0.1-arm64.pkg", "browser_download_url": "https://e.com/a.pkg", "size": 20, "digest": "sha256:ABCD"},
           {"name": "MacBatteryCharge-3.0.1-intel.pkg", "browser_download_url": "https://e.com/i.pkg", "size": 30}
         ]}
        """
        let release = try XCTUnwrap(ReleaseInfo.parse(Data(json.utf8)))
        XCTAssertEqual(release.version, "3.0.1")
        XCTAssertEqual(release.notes, "修好了")
        XCTAssertEqual(release.package(arm64: true)?.url.absoluteString, "https://e.com/a.pkg")
        XCTAssertEqual(release.package(arm64: true)?.sha256, "abcd")
        XCTAssertEqual(release.package(arm64: false)?.size, 30)
        XCTAssertNil(release.package(arm64: false)?.sha256)
        XCTAssertNil(ReleaseInfo.parse(Data("{}".utf8)))
    }

    func testPmset() {
        let custom = "Battery Power:\n lowpowermode         1\n sleep 1\nAC Power:\n lowpowermode         0\n"
        let state = LowPowerState.parse(custom: custom)
        XCTAssertEqual(state, LowPowerState(battery: 1, ac: 0), "低电量配置文本")
        XCTAssertEqual(state?.choice, .battery)
        XCTAssertNil(LowPowerState.parse(custom: "Battery Power:\n lowpowermode 1\n"), "缺电源段应失败")
        let power = LowPowerState.parse(custom: "Battery Power:\n powermode 1\nAC Power:\n powermode 2\n")
        XCTAssertEqual(power?.key, "powermode", "有的机型叫 powermode")
        XCTAssertEqual(power?.choice, .battery, "高性能不算低电量")
        XCTAssertNil(LowPowerState(battery: 0, ac: 1).choice, "只接电源时开没有对应项")
        XCTAssertEqual(LowPowerChoice.normalized("nope"), .off, "不认识的低电量选项按不用")
    }

    func testGuide() {
        let bodies = GuideCopy.bodies.joined(separator: "\n")
        XCTAssertEqual(GuideCopy.titles.count, 6, "引导是六步")
        XCTAssertEqual(GuideCopy.bodies.count, 6)
        XCTAssertTrue(GuideCopy.titles.joined().contains("刘海"), "引导讲刘海")
        XCTAssertTrue(bodies.contains("管理员"), "引导讲管理员密码")
        XCTAssertTrue(bodies.contains("放电帮手"), "引导讲放电帮手")
        XCTAssertTrue(GuideCopy.bodies.allSatisfy { $0.count <= 40 }, "每步正文不超过 40 个字")
        XCTAssertTrue(bodies.contains("最低 20%"), "引导讲放电下限")
        XCTAssertFalse(bodies.contains("完全磁盘"), "引导不索要磁盘权限")
        XCTAssertFalse(bodies.contains("辅助功能"), "引导不索要辅助功能")
        XCTAssertFalse(bodies.contains("屏幕录制"))
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
