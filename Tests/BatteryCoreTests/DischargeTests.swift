import XCTest
@testable import BatteryCore

final class DischargeTests: XCTestCase {
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

    func testDefaultsDischargeInDaytimeOnly() {
        let schedule = schedule()
        XCTAssertTrue(schedule.discharge(at: 6 * 60), "06:00 起放电到 80%")
        XCTAssertTrue(schedule.discharge(at: 20 * 60 + 59))
        XCTAssertFalse(schedule.discharge(at: 21 * 60), "21:00 起放开到 100%，不放电")
        XCTAssertFalse(schedule.discharge(at: 3 * 60))
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
        XCTAssertTrue(settings.intervals[0].discharge)
        settings.intervals[0].discharge = false
        settings.intervals[0].drift = 5
        let decoded = try XCTUnwrap(AppSettings.decode(settings.encoded()))
        XCTAssertFalse(decoded.intervals[0].discharge)
        XCTAssertEqual(decoded.intervals[0].drift, 5)
        XCTAssertEqual(decoded.notchIsland, true)

        // 2.x 的文件没有 discharge：低于 100% 的段默认放电，100% 的段不放。
        let legacy = """
        {"intervals":[{"start":"06:00","end":"21:00","limit":80,"lowPower":"off"},{"start":"21:00","end":"06:00","limit":100,"lowPower":"battery"}]}
        """
        let old = try XCTUnwrap(AppSettings.decode(Data(legacy.utf8)))
        XCTAssertTrue(old.intervals[0].discharge)
        XCTAssertFalse(old.intervals[1].discharge)
        XCTAssertEqual(old.intervals[0].drift, 0, "旧文件没有漂移，默认关")
    }

    func testDischargeOffDayRoundTrip() throws {
        var settings = AppSettings()
        XCTAssertNil(settings.dischargeOffDay)
        settings.dischargeOffDay = "2026-10-29"
        let decoded = try XCTUnwrap(AppSettings.decode(settings.encoded()))
        XCTAssertEqual(decoded.dischargeOffDay, "2026-10-29")
    }

    // MARK: 预测

    func testForecastDischargesThenHolds() {
        let points = Forecast.points(schedule: schedule(), minute: 6 * 60, percent: 95, external: true, deadline: nil,
                                     chargeRate: nil, dischargeAvailable: true, horizon: 480)
        XCTAssertEqual(points.first?.percent ?? 0, 95, accuracy: 0.01)
        XCTAssertTrue(points.contains { $0.discharging })
        XCTAssertEqual(points.last?.percent ?? 0, 80, accuracy: 0.01, "放到上限后停住")
        XCTAssertTrue(points.allSatisfy { $0.percent >= 80 - 0.01 })
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
