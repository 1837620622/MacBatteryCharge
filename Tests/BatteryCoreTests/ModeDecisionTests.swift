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
    func testOldSettingsFileStaysOnTheScheduleAndLearns() throws {
        let settings = try XCTUnwrap(AppSettings.decode(Data(#"{"intervals":[{"start":"06:00","end":"21:00","limit":80}]}"#.utf8)))
        XCTAssertEqual(settings.mode, .fixed)
        XCTAssertTrue(settings.learnHabits, "新加的习惯学习默认打开")
    }
}
