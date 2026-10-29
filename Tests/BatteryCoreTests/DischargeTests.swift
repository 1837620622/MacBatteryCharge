import XCTest
@testable import BatteryCore

final class DischargeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        pinChineseUI()
    }

    private func schedule() -> Schedule {
        guard case .success(let value) = Schedule.compile(Schedule.makeDefaults()) else { fatalError("默认时间表应该能编译") }
        return value
    }

    private func decision(_ limit: Int, _ reason: LimitReason = .schedule) -> LimitDecision {
        LimitDecision(limit: limit, reason: reason, scheduled: limit)
    }

    private func shouldDischarge(_ previous: Bool, _ percent: Int?, limit: Int = 80, resumeAt: Int? = nil,
                                 enabled: Bool = true, external: Bool = true) -> Bool {
        ChargePolicy.shouldDischarge(previous: previous, percent: percent, decision: decision(limit),
                                     enabled: enabled, external: external, resumeAt: resumeAt)
    }

    /// 默认时间表不主动放电：用户只装了这个软件，不该在不知情的时候看着电量往下掉。
    func testDefaultsDoNotDischarge() {
        let schedule = schedule()
        XCTAssertFalse(schedule.discharge(at: 6 * 60))
        XCTAssertFalse(schedule.discharge(at: 20 * 60 + 59))
        XCTAssertFalse(schedule.discharge(at: 21 * 60))
        XCTAssertFalse(schedule.discharge(at: 3 * 60))
        XCTAssertTrue(Schedule.makeDefaults().allSatisfy { !$0.discharge })
    }

    func testMarginKeepsNativeOvershootFromCycling() {
        // 苹果的上限会停在几个百分点之内。超过 80 三个点才开始放，放到 80 就接电，不在 80 和 82 之间来回。
        XCTAssertFalse(shouldDischarge(false, 82), "停在 82 不放")
        XCTAssertTrue(shouldDischarge(false, 83))
        XCTAssertTrue(shouldDischarge(true, 81), "放的途中继续放")
        XCTAssertFalse(shouldDischarge(true, 80), "放到上限就接电")
    }

    func testDriftStartsAtLimitAndResumesAtBottom() {
        // 漂移 5%：到 80 就开始放，掉到 75 才接电，中间自己漂。
        XCTAssertFalse(shouldDischarge(false, 79, resumeAt: 75))
        XCTAssertTrue(shouldDischarge(false, 80, resumeAt: 75))
        XCTAssertTrue(shouldDischarge(true, 76, resumeAt: 75))
        XCTAssertFalse(shouldDischarge(true, 75, resumeAt: 75))
    }

    func testNeverDischargesAtOrBelowFloor() {
        XCTAssertFalse(shouldDischarge(true, ChargePolicy.dischargeFloor, limit: 80, resumeAt: 75))
        XCTAssertFalse(shouldDischarge(true, 15, limit: 10))
        XCTAssertEqual(ChargePolicy.dischargeWindow(limit: 80, resumeAt: 10).resume, ChargePolicy.dischargeFloor, "漂移到再低也不低于 20")
    }

    func testShouldDischargeNeverWhenNotWanted() {
        XCTAssertFalse(shouldDischarge(true, 95, enabled: false), "这一段没开放电")
        XCTAssertFalse(shouldDischarge(true, 95, external: false), "没接电源")
        XCTAssertFalse(shouldDischarge(true, nil))
        XCTAssertFalse(shouldDischarge(true, 95, limit: 100), "100% 不放")
        for reason in [LimitReason.topUp, .deadline, .heat, .gap] {
            XCTAssertFalse(ChargePolicy.shouldDischarge(previous: true, percent: 95, decision: decision(80, reason),
                                                        enabled: true, external: true), "\(reason) 不放电")
        }
    }

    func testHeatThresholdsFollowApplePublishedRange() {
        XCTAssertEqual(ChargePolicy.heatOn, 35, "35°C 是我们选的保守阈值，不是苹果规定的电池温度")
        XCTAssertTrue(ChargePolicy.heatActive(previous: false, celsius: 35.5, external: true))
        XCTAssertTrue(ChargePolicy.heatActive(previous: true, celsius: 34, external: true), "中间保持")
        XCTAssertFalse(ChargePolicy.heatActive(previous: false, celsius: 34, external: true))
        XCTAssertFalse(ChargePolicy.heatActive(previous: true, celsius: 32.9, external: true))
        XCTAssertFalse(ChargePolicy.heatActive(previous: true, celsius: 45, external: false), "拔掉电源就解除")
    }

    // MARK: 漂移设置

    func testDriftOnlyCountsWhenDischarging() {
        XCTAssertEqual(Interval(start: ClockTime(hour: 6, minute: 0), end: ClockTime(hour: 21, minute: 0), limit: 80,
                                discharge: true, drift: 5).activeDrift, 5)
        XCTAssertEqual(Interval(start: ClockTime(hour: 6, minute: 0), end: ClockTime(hour: 21, minute: 0), limit: 80,
                                discharge: false, drift: 5).activeDrift, 0, "不放电就没有漂移")
        XCTAssertEqual(Interval(start: ClockTime(hour: 6, minute: 0), end: ClockTime(hour: 21, minute: 0), limit: 80,
                                discharge: true, drift: 7).activeDrift, 0, "只认 5 和 10")
        XCTAssertEqual(Interval(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 6, minute: 0), limit: 100,
                                discharge: true, drift: 5).activeDrift, 0, "100% 没有漂移")
        let item = Interval(start: ClockTime(hour: 6, minute: 0), end: ClockTime(hour: 21, minute: 0), limit: 80,
                            discharge: true, drift: 10)
        XCTAssertEqual(item.resumeAt, 70)
    }

    func testDayLineSummarisesTheDay() {
        let line = schedule().dayLine(deadline: ClockTime(hour: 23, minute: 30))
        XCTAssertEqual(line, "06:00 起 80% · 21:00 起 100% · 23:30 断电")
        XCTAssertEqual(schedule().dayLine(deadline: nil), "06:00 起 80% · 21:00 起 100%")
        XCTAssertEqual(Schedule.empty.dayLine(deadline: nil), "全天 100%")
    }

    // MARK: 帮手

    private func input(percent: Int?, external: Bool = true, sleeping: Bool = false, limit: Int? = nil, to: Int? = 80,
                       resume: Int? = nil, lease: Bool = true, charging: Bool = true, disabled: Bool = false) -> HelperPolicy.Input {
        HelperPolicy.Input(percent: percent, external: external, sleeping: sleeping, limit: limit, dischargeTo: to,
                           resumeAt: resume, leaseValid: lease, chargingBefore: charging, adapterDisabled: disabled)
    }

    func testHelperDischargesAboveMargin() {
        XCTAssertFalse(HelperPolicy.decide(input(percent: 92)).adapterOn)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 82)).adapterOn, "差 2% 不断电")
        XCTAssertFalse(HelperPolicy.decide(input(percent: 83)).adapterOn)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 80)).adapterOn)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 79)).adapterOn)
    }

    func testHelperDriftKeepsCutUntilResume() {
        XCTAssertFalse(HelperPolicy.decide(input(percent: 80, to: 80, resume: 75)).adapterOn, "到上限就开始断")
        XCTAssertTrue(HelperPolicy.decide(input(percent: 79, to: 80, resume: 75)).adapterOn, "没到上限不断")
        XCTAssertFalse(HelperPolicy.decide(input(percent: 79, to: 80, resume: 75, disabled: true)).adapterOn, "断着就一直断到 75")
        XCTAssertFalse(HelperPolicy.decide(input(percent: 76, external: false, to: 80, resume: 75, disabled: true)).adapterOn)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 75, to: 80, resume: 75, disabled: true)).adapterOn, "掉到 75 才接回")
    }

    func testHelperKeepsDischargingWhenSystemSaysNoPower() {
        // 断开适配器后系统会说没接电源，帮手不能因此半路接回又断开。
        XCTAssertFalse(HelperPolicy.decide(input(percent: 90, external: false, disabled: true)).adapterOn)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 90, external: false, disabled: false)).adapterOn, "本来就没接电源，没有可断的")
    }

    func testHelperRestoresPowerForSafety() {
        XCTAssertTrue(HelperPolicy.decide(input(percent: 95, lease: false)).adapterOn, "指令过期")
        XCTAssertTrue(HelperPolicy.decide(input(percent: 95, sleeping: true)).adapterOn, "睡眠")
        XCTAssertTrue(HelperPolicy.decide(input(percent: 95, to: nil)).adapterOn, "没有放电目标")
        XCTAssertTrue(HelperPolicy.decide(input(percent: 18, to: 5)).adapterOn, "20% 以下不断电")
        XCTAssertTrue(HelperPolicy.decide(input(percent: nil)).adapterOn)
    }

    func testHelperDirectChargeLimitHysteresis() {
        XCTAssertFalse(HelperPolicy.decide(input(percent: 80, limit: 80, to: nil)).chargingAllowed)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 75, limit: 80, to: nil, charging: false)).chargingAllowed)
        XCTAssertFalse(HelperPolicy.decide(input(percent: 76, limit: 80, to: nil, charging: false)).chargingAllowed, "回差内保持停充")
        XCTAssertTrue(HelperPolicy.decide(input(percent: 78, limit: 80, to: nil, charging: true)).chargingAllowed, "回差内保持充电")
        XCTAssertTrue(HelperPolicy.decide(input(percent: 90, limit: 100, to: nil)).chargingAllowed)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 90, limit: nil, to: nil)).chargingAllowed)
    }

    func testHelperNeverChargesWhileDischarging() {
        XCTAssertFalse(HelperPolicy.decide(input(percent: 92, limit: 80)).chargingAllowed)
    }

    func testProtocolRoundTrip() {
        let request = HelperRequest(cmd: .apply, limit: 80, dischargeTo: 80, resumeAt: 75, lease: 120)
        let line = HelperCoding.line(request)
        XCTAssertEqual(line.last, 0x0A)
        XCTAssertEqual(HelperRequest.decode(line.dropLast()), request)
        XCTAssertNil(HelperRequest.decode(Data("not json".utf8)))

        let status = HelperStatus(version: "3.0.0", adapterControl: true, chargeControl: .intelCeiling, adapterEnabled: false,
                                  percent: 90, external: false, dischargeTo: 80, leaseRemaining: 100)
        XCTAssertEqual(HelperStatus.decode(HelperCoding.line(status).dropLast()), status)
    }

    // MARK: 设置

    func testIntervalDischargeRoundTripAndLegacy() throws {
        var settings = AppSettings()
        XCTAssertFalse(settings.intervals[0].discharge, "新装默认不放电")
        settings.intervals[0].discharge = true
        settings.intervals[0].drift = 5
        let decoded = try XCTUnwrap(AppSettings.decode(settings.encoded()))
        XCTAssertTrue(decoded.intervals[0].discharge)
        XCTAssertEqual(decoded.intervals[0].drift, 5)
        XCTAssertEqual(decoded.notchIsland, true)

        // 旧文件没有 discharge 这一项：不推断，一律当作关。升级不能替用户打开主动放电。
        let legacy = """
        {"intervals":[{"start":"06:00","end":"21:00","limit":80,"lowPower":"off"},{"start":"21:00","end":"06:00","limit":100,"lowPower":"battery"}]}
        """
        let old = try XCTUnwrap(AppSettings.decode(Data(legacy.utf8)))
        XCTAssertFalse(old.intervals[0].discharge, "旧配置升级不能擅自开放电")
        XCTAssertFalse(old.intervals[1].discharge)
        XCTAssertEqual(old.intervals[0].drift, 0, "旧文件没有漂移，默认关")
        XCTAssertEqual(old.unplugTarget, 100, "旧文件没有离电目标，默认 100%")
    }

    func testUnplugTargetRoundTrip() throws {
        var settings = AppSettings()
        XCTAssertEqual(settings.unplugTarget, 100)
        settings.unplugTarget = 90
        let decoded = try XCTUnwrap(AppSettings.decode(settings.encoded()))
        XCTAssertEqual(decoded.unplugTarget, 90)
        // 文件里写了个不认识的数，落回最近的档位，不崩。
        let odd = try XCTUnwrap(AppSettings.decode(Data(#"{"unplugTarget": 91}"#.utf8)))
        XCTAssertEqual(odd.unplugTarget, 90)
        let huge = try XCTUnwrap(AppSettings.decode(Data(#"{"unplugTarget": 500}"#.utf8)))
        XCTAssertEqual(huge.unplugTarget, 100)
    }

    func testDischargeOffDayRoundTrip() throws {
        var settings = AppSettings()
        XCTAssertNil(settings.dischargeOffDay)
        settings.dischargeOffDay = "2026-10-29"
        let decoded = try XCTUnwrap(AppSettings.decode(settings.encoded()))
        XCTAssertEqual(decoded.dischargeOffDay, "2026-10-29")
    }

    // MARK: 预测

    func testForecastDischargesThenHolds() throws {
        let schedule = try XCTUnwrap(Schedule.compile([
            Interval(start: ClockTime(hour: 6, minute: 0), end: ClockTime(hour: 21, minute: 0), limit: 80, discharge: true),
            Interval(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 6, minute: 0), limit: 100),
        ]).get())
        let points = Forecast.points(schedule: schedule, minute: 6 * 60, percent: 95, external: true, deadline: nil,
                                     chargeRate: nil, dischargeAvailable: true, horizon: 480)
        XCTAssertEqual(points.first?.percent ?? 0, 95, accuracy: 0.01)
        XCTAssertTrue(points.contains { $0.discharging })
        XCTAssertEqual(points.last?.percent ?? 0, 80, accuracy: 0.01, "放到上限后停住")
        XCTAssertTrue(points.allSatisfy { $0.percent >= 80 - 0.01 })
    }

    /// 默认时间表（不放电）下，超上限也应该停在原地，不能往下掉。
    func testForecastWithDefaultScheduleNeverDischarges() {
        let points = Forecast.points(schedule: schedule(), minute: 6 * 60, percent: 95, external: true, deadline: nil,
                                     chargeRate: nil, dischargeAvailable: true, horizon: 480)
        XCTAssertFalse(points.contains { $0.discharging }, "默认不放电")
        XCTAssertTrue(points.allSatisfy { $0.percent == 95 })
    }

    func testForecastWithoutHelperHolds() {
        let points = Forecast.points(schedule: schedule(), minute: 6 * 60, percent: 95, external: true, deadline: nil,
                                     chargeRate: nil, dischargeAvailable: false, horizon: 240)
        XCTAssertTrue(points.allSatisfy { $0.percent == 95 }, "没有帮手只停充，不往下放")
    }

    func testForecastDriftCyclesBetweenResumeAndLimit() throws {
        let drifting = try XCTUnwrap(Schedule.compile([
            Interval(start: ClockTime(hour: 6, minute: 0), end: ClockTime(hour: 21, minute: 0), limit: 80, discharge: true, drift: 5),
            Interval(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 6, minute: 0), limit: 100),
        ]).get())
        let points = Forecast.points(schedule: drifting, minute: 6 * 60, percent: 95, external: true, deadline: nil,
                                     chargeRate: nil, dischargeAvailable: true, horizon: 600)
        let settled = points.filter { $0.minutesAhead >= 120 }
        XCTAssertFalse(settled.isEmpty)
        XCTAssertTrue(settled.allSatisfy { $0.percent >= 75 - 0.01 && $0.percent <= 80 + 0.01 }, "漂移只在 75 到 80 之间")
        XCTAssertLessThan(settled.map(\.percent).min() ?? 100, 75.5, "会掉到 75 再接电")
        XCTAssertGreaterThan(settled.map(\.percent).max() ?? 0, 79.5, "也会充回 80")
    }

    func testForecastChargesAtNight() {
        let points = Forecast.points(schedule: schedule(), minute: 21 * 60, percent: 80, external: true,
                                     deadline: ClockTime(hour: 23, minute: 30), chargeRate: 0.33,
                                     dischargeAvailable: true, horizon: 480)
        XCTAssertGreaterThan(points.last?.percent ?? 0, 99)
        XCTAssertEqual(points.last?.minutesAhead, 150, "预测到断电为止")
    }

    func testForecastOnBatteryDrains() {
        let points = Forecast.points(schedule: schedule(), minute: 23 * 60 + 40, percent: 100, external: false,
                                     deadline: nil, chargeRate: nil, dischargeAvailable: true, horizon: 120)
        XCTAssertLessThan(points.last?.percent ?? 100, 90)
    }
}

// MARK: 模式

final class ModeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        pinChineseUI()
    }

    private func compiled(_ items: [Interval]) -> Schedule {
        guard case .success(let schedule) = Schedule.compile(items) else { fatalError("时间表应能通过") }
        return schedule
    }

    /// 智能模式平时停在日常上限，不因为「有离电时间」就往上放。
    func testSmartStopsAtDailyCapWhenFarFromDeadline() {
        let decision = SmartPolicy.decide(SmartInput(percent: 60, external: true, minute: 9 * 60,
                                                    dailyCap: 80, unplugTarget: 100,
                                                    deadline: ClockTime(hour: 23, minute: 30), rate: 0.33))
        XCTAssertEqual(decision.decision.limit, 80, "离电还早，停在 80%")
        XCTAssertEqual(decision.decision.reason, .smart)
        XCTAssertFalse(decision.learned)
    }

    /// 离电前来不及了才放开，放开到离电目标。
    func testSmartLiftsBeforeDeadline() {
        let deadline = ClockTime(hour: 23, minute: 30)
        let early = SmartPolicy.decide(SmartInput(percent: 80, external: true, minute: 21 * 60,
                                                  dailyCap: 80, unplugTarget: 100, deadline: deadline, rate: 0.33))
        XCTAssertEqual(early.decision.limit, 80, "21:00 还来得及，先不放")
        let late = SmartPolicy.decide(SmartInput(percent: 80, external: true, minute: 22 * 60 + 30,
                                                 dailyCap: 80, unplugTarget: 100, deadline: deadline, rate: 0.33))
        XCTAssertEqual(late.decision.limit, 100, "只剩一小时，要放开")
        XCTAssertEqual(late.decision.reason, .deadline)
    }

    /// 学到的拔电时间优先于用户设的时间。
    func testSmartPrefersLearnedUnplugTime() {
        let input = SmartInput(percent: 80, external: true, minute: 18 * 60, dailyCap: 80, unplugTarget: 100,
                               deadline: ClockTime(hour: 8, minute: 0),
                               learnedUnplug: ClockTime(hour: 18, minute: 40), rate: 0.33)
        let decision = SmartPolicy.decide(input)
        XCTAssertTrue(decision.learned)
        XCTAssertEqual(decision.deadline?.text, "18:40")
        XCTAssertEqual(decision.decision.limit, 100, "40 分钟只够充 20%，立刻放开")
    }

    /// 没有离电时间就只守日常上限，不猜。
    func testSmartWithoutDeadlineStaysAtCap() {
        let decision = SmartPolicy.decide(SmartInput(percent: 95, external: true, minute: 12 * 60, dailyCap: 80))
        XCTAssertEqual(decision.decision.limit, 80)
        XCTAssertNil(decision.plan)
    }

    /// 电池偏热时不去追满电。
    func testSmartRespectsHeat() {
        let decision = SmartPolicy.decide(SmartInput(percent: 80, external: true, minute: 23 * 60,
                                                    dailyCap: 90, unplugTarget: 100,
                                                    deadline: ClockTime(hour: 23, minute: 30),
                                                    rate: 0.33, heat: true))
        XCTAssertEqual(decision.decision.limit, 80, "热的时候最高 80%")
        XCTAssertEqual(decision.decision.reason, .heat)
    }

    func testSmartDailyCapClamping() {
        XCTAssertEqual(SmartPolicy.clampDailyCap(80), 80)
        XCTAssertEqual(SmartPolicy.clampDailyCap(88), 90)
        XCTAssertEqual(SmartPolicy.clampDailyCap(50), 80)
        XCTAssertEqual(SmartPolicy.clampDailyCap(100), 95, "智能模式没有 100 这一档，要 100 请用「一直充满」")
    }

    /// 只有固定模式能主动放电。
    func testOnlyFixedModeDischarges() {
        XCTAssertTrue(ChargeMode.fixed.allowsDischarge)
        XCTAssertFalse(ChargeMode.smart.allowsDischarge)
        XCTAssertFalse(ChargeMode.full.allowsDischarge)
    }

    /// 旧设置没有 mode：升级过来是固定时间表，不是智能。
    func testLegacySettingsBecomeFixedMode() throws {
        let old = try XCTUnwrap(AppSettings.decode(Data(#"{"intervals":[]}"#.utf8)))
        XCTAssertEqual(old.mode, .fixed, "老配置的行为就是按时间表，升级不能变成智能")
        let fresh = AppSettings()
        XCTAssertEqual(fresh.mode, .smart, "新装默认智能")
        var saved = fresh
        saved.mode = .full
        XCTAssertEqual(try XCTUnwrap(AppSettings.decode(saved.encoded())).mode, .full)
    }

    /// 学拔电时间：同一档里出现最多的那次。
    func testLearnedUnplugTime() {
        let calendar = Calendar(identifier: .gregorian)
        var history = ChargeHistory()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        func stamp(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(byAdding: .day, value: dayOffset,
                          to: calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!)!
        }
        for offset in 0..<4 {
            history.add(ChargeSample(t: stamp(offset, 18, 20), p: 80, c: false, x: true, l: 80))
            history.add(ChargeSample(t: stamp(offset, 18, 42), p: 80, c: false, x: false, l: 80))
        }
        XCTAssertEqual(history.learnedUnplug()?.text, "18:42", "四次都在 18:40 前后拔电源")
        var few = ChargeHistory()
        few.add(ChargeSample(t: stamp(0, 18, 20), p: 80, c: false, x: true, l: 80))
        few.add(ChargeSample(t: stamp(0, 18, 42), p: 80, c: false, x: false, l: 80))
        XCTAssertNil(few.learnedUnplug(), "次数太少不猜")
    }
}
