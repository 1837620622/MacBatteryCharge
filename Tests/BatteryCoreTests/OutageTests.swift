import XCTest
@testable import BatteryCore

/// 工作日停电：周一到周五的晚上停电，周末不停。跨过午夜的那段算开始那天的。
final class OutageTests: XCTestCase {
    private func at(_ hour: Int, _ minute: Int) -> Int { hour * 60 + minute }
    private let sunday = 1, monday = 2, tuesday = 3, friday = 6, saturday = 7
    private let start = ClockTime(hour: 23, minute: 30)
    private let end = ClockTime(hour: 6, minute: 0)

    private func out(_ minute: Int, _ weekday: Int) -> Bool {
        Outage.isOut(minute: minute, weekday: weekday, start: start, end: end)
    }

    func testWorkdaysAreMondayToFriday() {
        XCTAssertFalse(Outage.isWorkday(weekday: sunday))
        for weekday in monday...friday { XCTAssertTrue(Outage.isWorkday(weekday: weekday)) }
        XCTAssertFalse(Outage.isWorkday(weekday: saturday))
    }

    func testWeekdayNightIsOutageFromStartToEnd() {
        XCTAssertFalse(out(at(23, 29), monday), "23:29 还没停")
        XCTAssertTrue(out(at(23, 30), monday), "23:30 起停电")
        XCTAssertTrue(out(at(23, 59), monday))
        XCTAssertTrue(out(at(0, 0), tuesday), "周一晚上的停电一直到周二凌晨")
        XCTAssertTrue(out(at(5, 59), tuesday))
        XCTAssertFalse(out(at(6, 0), tuesday), "06:00 来电")
        XCTAssertFalse(out(at(12, 0), tuesday), "白天有电")
    }

    func testFridayNightCarriesIntoSaturdayMorning() {
        XCTAssertTrue(out(at(23, 30), friday))
        XCTAssertTrue(out(at(3, 0), saturday), "周五晚上的停电算到周六早上")
        XCTAssertFalse(out(at(23, 30), saturday), "周六晚上在家，不停电")
    }

    func testSundayNightDoesNotCutMondayMorning() {
        XCTAssertFalse(out(at(23, 30), sunday), "周日晚上不停")
        XCTAssertFalse(out(at(3, 0), monday), "周一凌晨是周日晚上的延续，不停")
    }

    func testSameDayWindowOnlyCountsToday() {
        let from = ClockTime(hour: 1, minute: 0), to = ClockTime(hour: 6, minute: 0)
        XCTAssertTrue(Outage.isOut(minute: at(3, 0), weekday: monday, start: from, end: to))
        XCTAssertFalse(Outage.isOut(minute: at(3, 0), weekday: saturday, start: from, end: to), "周六不停")
        XCTAssertFalse(Outage.isOut(minute: at(0, 30), weekday: monday, start: from, end: to))
    }

    func testEqualStartAndEndMeansNoOutage() {
        XCTAssertFalse(Outage.isOut(minute: at(3, 0), weekday: monday, start: start, end: start))
    }

    func testOutageSettingsAreOffByDefaultAndRoundTrip() throws {
        let fresh = AppSettings()
        XCTAssertFalse(fresh.outageEnabled, "默认不开，老用户不受影响")
        XCTAssertEqual(fresh.outageStart.text, "23:30")
        XCTAssertEqual(fresh.outageEnd.text, "06:00")

        var changed = AppSettings()
        changed.outageEnabled = true
        changed.outageStart = ClockTime(hour: 22, minute: 45)
        changed.outageEnd = ClockTime(hour: 7, minute: 15)
        let decoded = try XCTUnwrap(AppSettings.decode(try changed.encoded()))
        XCTAssertTrue(decoded.outageEnabled)
        XCTAssertEqual(decoded.outageStart.text, "22:45")
        XCTAssertEqual(decoded.outageEnd.text, "07:15")
    }

    func testOldSettingsFileGetsOutageDefaults() throws {
        let json = #"{"mode":"smart","learnHabits":true}"#
        let settings = try XCTUnwrap(AppSettings.decode(Data(json.utf8)))
        XCTAssertFalse(settings.outageEnabled)
        XCTAssertEqual(settings.outageStart.text, "23:30")
        XCTAssertEqual(settings.outageEnd.text, "06:00")
    }
}
