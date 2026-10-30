import XCTest
@testable import BatteryCore

/// 三种模式每一步到底给系统写多少。这些是产品承诺，改逻辑时先看这里。
final class ModeDecisionTests: XCTestCase {
    private func at(_ hour: Int, _ minute: Int) -> Int { hour * 60 + minute }

    // MARK: 智能

    func testSmartHoldsDailyCapWhenNothingIsKnown() {
        let input = SmartInput(percent: 60, external: true, minute: at(10, 0), dailyCap: 80, unplugTarget: 100)
        let result = SmartPolicy.decide(input)
        XCTAssertEqual(result.decision.limit, 80, "平时停在日常上限")
        XCTAssertEqual(result.decision.reason, .smart)
        XCTAssertNil(result.plan, "没有离电时间就不做备电计划")
    }

    /// 60% 充到 100% 大约要 122 分钟。18:30 离电：15:00 还不必放开，17:00 必须放开。
    func testSmartLiftsOnlyWhenTheMathSaysSo() {
        let learned = ClockTime(hour: 18, minute: 30)
        let early = SmartPolicy.decide(SmartInput(percent: 60, external: true, minute: at(15, 0), dailyCap: 80,
                                                  unplugTarget: 100, learnedUnplug: learned))
        XCTAssertEqual(early.decision.limit, 80, "15:00 还来得及慢慢充")
        XCTAssertTrue(early.learned)

        let late = SmartPolicy.decide(SmartInput(percent: 60, external: true, minute: at(17, 0), dailyCap: 80,
                                                 unplugTarget: 100, learnedUnplug: learned))
        XCTAssertEqual(late.decision.limit, 100)
        XCTAssertEqual(late.decision.reason, .deadline)
    }

    /// 没学会之前，按用户设的默认拔电时间备电。
    func testSmartFallsBackToTheDefaultTimeBeforeLearning() {
        let input = SmartInput(percent: 60, external: true, minute: at(22, 30), dailyCap: 80, unplugTarget: 100,
                               deadline: ClockTime(hour: 23, minute: 30), learnedUnplug: nil)
        let result = SmartPolicy.decide(input)
        XCTAssertFalse(result.learned)
        XCTAssertEqual(result.decision.limit, 100)
    }

    /// 过了离电时间还插着电源：不再放开，回到日常上限。
    func testSmartGoesBackToCapAfterTheUnplugTime() {
        let input = SmartInput(percent: 60, external: true, minute: at(19, 0), dailyCap: 80, unplugTarget: 100,
                               learnedUnplug: ClockTime(hour: 18, minute: 30))
        let result = SmartPolicy.decide(input)
        XCTAssertEqual(result.decision.limit, 80)
        XCTAssertNil(result.plan)
    }

    func testSmartTopUpGoesToFullAndHeatStillWins() {
        let top = SmartPolicy.decide(SmartInput(percent: 60, external: true, minute: at(10, 0), dailyCap: 80,
                                                unplugTarget: 100, topUp: true))
        XCTAssertEqual(top.decision.limit, 100, "临时充满")
        XCTAssertEqual(top.decision.reason, .topUp)

        let hot = SmartPolicy.decide(SmartInput(percent: 60, external: true, minute: at(17, 0), dailyCap: 80,
                                                unplugTarget: 100, learnedUnplug: ClockTime(hour: 18, minute: 30),
                                                heat: true, topUp: true))
        XCTAssertEqual(hot.decision.limit, 80, "热的时候不追满电")
        XCTAssertEqual(hot.decision.reason, .heat)
    }

    // MARK: 一直充满

    /// 一直充满模式也要过热保护：偏热时停在 80%，凉下来再回到 100%。
    func testFullModeIsHundredUnlessHot() {
        let base = LimitDecision(limit: 100, reason: .full, scheduled: 100)
        XCTAssertEqual(ChargePolicy.applyHeat(base, heat: false), base)
        let hot = ChargePolicy.applyHeat(base, heat: true)
        XCTAssertEqual(hot.limit, 80)
        XCTAssertEqual(hot.reason, .heat)
    }

    // MARK: 固定时间表

    /// 时间表 80% 到 23:00，之后 100%。23:30 断电，充到 100% 要约 61 分钟。
    /// 20:00 还早，22:40 必须放开。
    func testFixedDeadlineLiftsOnlyWhenNeeded() throws {
        let schedule = try XCTUnwrap(Schedule.compile([
            Interval(start: ClockTime(hour: 6, minute: 0), end: ClockTime(hour: 23, minute: 0), limit: 80),
            Interval(start: ClockTime(hour: 23, minute: 0), end: ClockTime(hour: 6, minute: 0), limit: 100),
        ]).get())
        let deadline = ClockTime(hour: 23, minute: 30)
        let early = ChargePlanner.plan(schedule: schedule, minute: at(20, 0), percent: 80, deadline: deadline,
                                       target: 100, rate: nil)
        XCTAssertEqual(early?.liftNow, false)
        let late = ChargePlanner.plan(schedule: schedule, minute: at(22, 40), percent: 80, deadline: deadline,
                                      target: 100, rate: nil)
        XCTAssertEqual(late?.liftNow, true)
    }

    /// 没有断电时间的固定模式，就是时间表本身：不做额外的放开。
    func testFixedModeWithoutDeadlineUsesOnlyTheSchedule() throws {
        let schedule = try XCTUnwrap(Schedule.compile(Schedule.makeDefaults()).get())
        let decision = ChargePolicy.decide(schedule: schedule, minute: at(10, 0), topUp: false, deadlineLift: nil, heat: false)
        XCTAssertEqual(decision.limit, 80)
        XCTAssertEqual(decision.reason, .schedule)
    }

    // MARK: 旧文件

    /// 没有 mode 这一项的老文件，行为就是按时间表，所以升级后是固定模式，不是智能。
    /// 离电那一分钟（剩 0 分钟）还要把离电目标留住，不能在最后一分钟掉回日常上限。
    func testSmartPlanStillLiftsAtTheDeadlineMinute() throws {
        let plan = try XCTUnwrap(ChargePlanner.plan(minute: at(22, 0), percent: 60, deadline: ClockTime(hour: 22, minute: 0),
                                                    target: 100, base: 80, rate: nil))
        XCTAssertEqual(plan.minutesToDeadline, 0)
        XCTAssertTrue(plan.liftNow)
    }

    /// 时间表版本在离电那一分钟也不能崩（循环范围是 1..<0 时会越界）。
    func testSchedulePlanAtTheDeadlineMinuteDoesNotTrap() {
        let flat = SmartPolicy.flatSchedule(cap: 80)
        let plan = ChargePlanner.plan(schedule: flat, minute: at(22, 0), percent: 60, deadline: ClockTime(hour: 22, minute: 0),
                                      target: 100, rate: nil)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.minutesToDeadline, 0)
    }

    /// 读数缺一下：只有「正在放电」且缺得不久，才保持放电；开始放电必须读数完整。
    func testDischargeHoldsThroughAShortReadingGap() {
        XCTAssertTrue(ChargePolicy.keepsDischargingThroughGap(previous: true, readingUsable: false, secondsSinceUsable: 10))
        XCTAssertFalse(ChargePolicy.keepsDischargingThroughGap(previous: true, readingUsable: false, secondsSinceUsable: 90))
        XCTAssertFalse(ChargePolicy.keepsDischargingThroughGap(previous: false, readingUsable: false, secondsSinceUsable: 10))
        XCTAssertFalse(ChargePolicy.keepsDischargingThroughGap(previous: true, readingUsable: true, secondsSinceUsable: 0))
    }

    /// 低电量：夜间（18:00 到次日 06:00）才可能开；白天充电一律关；充完电也关。
    func testLowPowerOnlyAtNightWhileCharging() {
        XCTAssertFalse(LowPowerPolicy.isNight(at(17, 59)), "17:59 还是白天")
        XCTAssertTrue(LowPowerPolicy.isNight(at(18, 0)), "18:00 起算夜间")
        XCTAssertTrue(LowPowerPolicy.isNight(at(5, 59)), "凌晨 05:59 还是夜间")
        XCTAssertFalse(LowPowerPolicy.isNight(at(6, 0)), "06:00 起是白天")
        XCTAssertTrue(LowPowerPolicy.wantsWhileCharging(minute: at(21, 0), chargeDone: false), "夜间充电、没充完：开")
        XCTAssertFalse(LowPowerPolicy.wantsWhileCharging(minute: at(21, 0), chargeDone: true), "夜间充完电：关")
        XCTAssertFalse(LowPowerPolicy.wantsWhileCharging(minute: at(10, 0), chargeDone: false), "白天充电：关")
    }

    /// 预测用的「整天停在上限」时间表：不能有空档（空档是 100%），每一分钟都是这个上限。
    func testSmartForecastScheduleHoldsTheCapAllDay() {
        let flat = SmartPolicy.flatSchedule(cap: 85)
        XCTAssertFalse((0..<1440).contains { flat.isGap(at: $0) }, "整天没有空档")
        XCTAssertTrue((0..<1440).allSatisfy { flat.limit(at: $0) == 85 })
    }

    /// 预测和实际执行要用同一套算法：拿整天停在上限的时间表算出来的放开时间，要和智能模式实际用的一样。
    func testSmartForecastMatchesWhatSmartModeDoes() throws {
        let flat = SmartPolicy.flatSchedule(cap: 80)
        let deadline = ClockTime(hour: 18, minute: 30)
        for hour in [14, 16, 17] {
            let minute = at(hour, 0)
            let fromSchedule = ChargePlanner.plan(schedule: flat, minute: minute, percent: 60, deadline: deadline,
                                                  target: 100, rate: nil, window: 1439)
            let fromSmart = ChargePlanner.plan(minute: minute, percent: 60, deadline: deadline, target: 100,
                                               base: 80, rate: nil, window: 1439)
            XCTAssertEqual(fromSchedule?.liftNow, fromSmart?.liftNow, "\(hour):00")
            XCTAssertEqual(fromSchedule?.etaMinutes, fromSmart?.etaMinutes, "\(hour):00")
        }
    }

    func testOldSettingsFileStaysOnTheScheduleAndLearns() throws {
        let settings = try XCTUnwrap(AppSettings.decode(Data(#"{"intervals":[{"start":"06:00","end":"21:00","limit":80}]}"#.utf8)))
        XCTAssertEqual(settings.mode, .fixed)
        XCTAssertTrue(settings.learnHabits, "新加的习惯学习默认打开")
    }
}
