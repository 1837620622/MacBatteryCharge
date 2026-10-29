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

    func testDefaultsDischargeInDaytimeOnly() {
        let schedule = schedule()
        XCTAssertTrue(schedule.discharge(at: 6 * 60), "06:00 起放电到 80%")
        XCTAssertTrue(schedule.discharge(at: 20 * 60 + 59))
        XCTAssertFalse(schedule.discharge(at: 21 * 60), "21:00 起放开到 100%，不放电")
        XCTAssertFalse(schedule.discharge(at: 3 * 60))
    }

    func testShouldDischargeHysteresis() {
        // 高出上限 2% 才开始放，放到上限就停，避免 80/81 之间来回开关。
        XCTAssertFalse(ChargePolicy.shouldDischarge(previous: false, percent: 81, decision: decision(80), enabled: true, external: true))
        XCTAssertTrue(ChargePolicy.shouldDischarge(previous: false, percent: 82, decision: decision(80), enabled: true, external: true))
        XCTAssertTrue(ChargePolicy.shouldDischarge(previous: true, percent: 81, decision: decision(80), enabled: true, external: true))
        XCTAssertFalse(ChargePolicy.shouldDischarge(previous: true, percent: 80, decision: decision(80), enabled: true, external: true))
    }

    func testShouldDischargeNeverWhenNotWanted() {
        XCTAssertFalse(ChargePolicy.shouldDischarge(previous: true, percent: 95, decision: decision(80), enabled: false, external: true), "这一段没开放电")
        XCTAssertFalse(ChargePolicy.shouldDischarge(previous: true, percent: 95, decision: decision(80), enabled: true, external: false), "没接电源")
        XCTAssertFalse(ChargePolicy.shouldDischarge(previous: true, percent: nil, decision: decision(80), enabled: true, external: true))
        for reason in [LimitReason.topUp, .deadline, .heat, .gap] {
            XCTAssertFalse(ChargePolicy.shouldDischarge(previous: true, percent: 95, decision: decision(100, reason), enabled: true, external: true), "\(reason) 不放电")
        }
    }

    func testDischargeFloor() {
        // 上限再低也不放到 20% 以下。
        XCTAssertFalse(ChargePolicy.shouldDischarge(previous: true, percent: 20, decision: decision(10), enabled: true, external: true))
        XCTAssertTrue(ChargePolicy.shouldDischarge(previous: true, percent: 25, decision: decision(10), enabled: true, external: true))
    }

    // MARK: 帮手

    private func input(percent: Int?, external: Bool = true, sleeping: Bool = false, limit: Int? = nil, to: Int? = 80,
                       lease: Bool = true, charging: Bool = true, disabled: Bool = false) -> HelperPolicy.Input {
        HelperPolicy.Input(percent: percent, external: external, sleeping: sleeping, limit: limit, dischargeTo: to,
                           leaseValid: lease, chargingBefore: charging, adapterDisabled: disabled)
    }

    func testHelperDischargesAboveTarget() {
        XCTAssertFalse(HelperPolicy.decide(input(percent: 92)).adapterOn)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 80)).adapterOn)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 79)).adapterOn)
    }

    func testHelperKeepsDischargingWhenSystemSaysNoPower() {
        // 断开适配器后系统会说没接电源，帮手不能因此半路接回来又断开。
        XCTAssertFalse(HelperPolicy.decide(input(percent: 90, external: false, disabled: true)).adapterOn)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 90, external: false, disabled: false)).adapterOn, "本来就没接电源，没有可断的")
    }

    func testHelperRestoresPowerForSafety() {
        XCTAssertTrue(HelperPolicy.decide(input(percent: 95, lease: false)).adapterOn, "指令过期")
        XCTAssertTrue(HelperPolicy.decide(input(percent: 95, sleeping: true)).adapterOn, "睡眠")
        XCTAssertTrue(HelperPolicy.decide(input(percent: 95, to: nil)).adapterOn, "没有放电目标")
        XCTAssertTrue(HelperPolicy.decide(input(percent: 18, to: 5)).adapterOn, "不低于 20%")
        XCTAssertTrue(HelperPolicy.decide(input(percent: nil)).adapterOn)
    }

    func testHelperDirectChargeLimitHysteresis() {
        XCTAssertFalse(HelperPolicy.decide(input(percent: 80, limit: 80, to: nil)).chargingAllowed)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 77, limit: 80, to: nil, charging: false)).chargingAllowed)
        XCTAssertFalse(HelperPolicy.decide(input(percent: 78, limit: 80, to: nil, charging: false)).chargingAllowed, "回差内保持停充")
        XCTAssertTrue(HelperPolicy.decide(input(percent: 78, limit: 80, to: nil, charging: true)).chargingAllowed, "回差内保持充电")
        XCTAssertTrue(HelperPolicy.decide(input(percent: 90, limit: 100, to: nil)).chargingAllowed)
        XCTAssertTrue(HelperPolicy.decide(input(percent: 90, limit: nil, to: nil)).chargingAllowed)
    }

    func testHelperNeverChargesWhileDischarging() {
        XCTAssertFalse(HelperPolicy.decide(input(percent: 92, limit: 80)).chargingAllowed)
    }

    func testProtocolRoundTrip() throws {
        let request = HelperRequest(cmd: .apply, limit: 80, dischargeTo: 80, lease: 120)
        let line = HelperCoding.line(request)
        XCTAssertEqual(line.last, 0x0A)
        XCTAssertEqual(HelperRequest.decode(line.dropLast()), request)
        XCTAssertNil(HelperRequest.decode(Data("not json".utf8)))

        let status = HelperStatus(version: "3.0.0", adapterControl: true, chargeControl: .system, adapterEnabled: false,
                                  percent: 90, external: false, dischargeTo: 80, leaseRemaining: 100)
        XCTAssertEqual(HelperStatus.decode(HelperCoding.line(status).dropLast()), status)
        XCTAssertTrue(status.adapterEnabled == false)
    }

    // MARK: 设置

    func testIntervalDischargeRoundTripAndLegacy() throws {
        var settings = AppSettings()
        XCTAssertTrue(settings.intervals[0].discharge)
        settings.intervals[0].discharge = false
        let decoded = try XCTUnwrap(AppSettings.decode(settings.encoded()))
        XCTAssertFalse(decoded.intervals[0].discharge)
        XCTAssertEqual(decoded.notchIsland, true)

        // 2.x 的文件没有 discharge：低于 100% 的段默认放电，100% 的段不放。
        let legacy = """
        {"intervals":[{"start":"06:00","end":"21:00","limit":80,"lowPower":"off"},{"start":"21:00","end":"06:00","limit":100,"lowPower":"battery"}]}
        """
        let old = try XCTUnwrap(AppSettings.decode(Data(legacy.utf8)))
        XCTAssertTrue(old.intervals[0].discharge)
        XCTAssertFalse(old.intervals[1].discharge)
    }

    // MARK: 预测

    func testForecastDischargesThenHolds() {
        let schedule = schedule()
        let points = Forecast.points(schedule: schedule, minute: 6 * 60, percent: 95, external: true, deadline: nil,
                                     chargeRate: nil, dischargeAvailable: true, horizon: 480)
        XCTAssertEqual(points.first?.percent, 95)
        XCTAssertTrue(points.contains { $0.discharging })
        XCTAssertEqual(points.last?.percent ?? 0, 80, accuracy: 0.01, "放到上限后停住")
        XCTAssertTrue(points.allSatisfy { $0.percent >= 80 - 0.01 })
    }

    func testForecastWithoutHelperHolds() {
        let points = Forecast.points(schedule: schedule(), minute: 6 * 60, percent: 95, external: true, deadline: nil,
                                     chargeRate: nil, dischargeAvailable: false, horizon: 240)
        XCTAssertTrue(points.allSatisfy { $0.percent == 95 }, "没有帮手只停充，不往下放")
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
