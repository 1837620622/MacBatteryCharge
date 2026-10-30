import XCTest
@testable import BatteryCore

final class JournalTests: XCTestCase {
    override func setUp() {
        super.setUp()
        pinChineseUI()
    }

    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func minutes(_ value: Int) -> Date { base.addingTimeInterval(Double(value) * 60) }

    private func sample(_ minute: Int, percent: Int, external: Bool, limit: Int = 80) -> ChargeSample {
        ChargeSample(t: minutes(minute), p: percent, c: false, x: external, l: limit)
    }

    /// 一天一行的累加：电量高低、接电源和用电池的时长、挂满的时长。
    func testDayTotals() {
        var journal = HabitJournal()
        var previous: ChargeSample?
        let series: [ChargeSample] = [
            sample(0, percent: 100, external: true),
            sample(10, percent: 100, external: true),
            sample(20, percent: 100, external: true),
            sample(30, percent: 82, external: false),
            sample(40, percent: 80, external: false),
            sample(50, percent: 81, external: true),
        ]
        for value in series {
            journal.absorb(value, previous: previous, day: "2026-10-29")
            previous = value
        }
        let today = try? XCTUnwrap(journal.today)
        XCTAssertEqual(today?.lo, 80)
        XCTAssertEqual(today?.hi, 100)
        XCTAssertEqual(today?.powerMinutes, 30, "前三次读数之间是接电源的 30 分钟")
        XCTAssertEqual(today?.batteryMinutes, 20, "中间两次是用电池的 20 分钟")
        XCTAssertEqual(today?.fullMinutes, 30, "20 到 30 分那一段也是接着电源、满电")
    }

    /// 长时间没读数（程序没在跑）不能算成一直插着。
    func testGapIsNotCounted() {
        var journal = HabitJournal()
        let first = sample(0, percent: 80, external: true)
        journal.absorb(first, previous: nil, day: "2026-10-29")
        journal.absorb(sample(300, percent: 80, external: true), previous: first, day: "2026-10-29")
        XCTAssertEqual(journal.today?.powerMinutes, 0)
    }

    /// 读数的间隔可能只有 30 秒（窗口关着）或 2 秒（窗口开着）。不满一分钟的间隔也要算进时长，不能取整成 0。
    func testShortSampleIntervalsAreCounted() {
        var journal = HabitJournal()
        var previous: ChargeSample?
        for step in 0...240 {
            let current = ChargeSample(t: base.addingTimeInterval(Double(step) * 30), p: 90, c: false, x: false, l: 80)
            journal.absorb(current, previous: previous, day: "2026-10-29")
            previous = current
        }
        XCTAssertEqual(Double(journal.today?.batteryMinutes ?? 0), 120, accuracy: 0.5, "两小时用电池，每 30 秒一个读数")
        XCTAssertEqual(Double(journal.today?.powerMinutes ?? 0), 0, accuracy: 0.5)
    }

    /// 一小时之内记下三次就学会，取中间那次。不能因为正好跨过半点就学不会。
    func testThreeWithinAnHourAreLearnedAcrossHalfHours() {
        let times = [20 * 60 + 25, 20 * 60 + 40, 20 * 60 + 55]
        XCTAssertEqual(HabitJournal.cluster(times, minSamples: 3), ClockTime(minuteOfDay: 20 * 60 + 40))
    }

    /// 23 点半和 0 点 10 分是同一个习惯，不能被分成两群。
    func testLateNightCountsAsTheSameNight() {
        let times = [23 * 60 + 40, 10, 20]
        XCTAssertEqual(HabitJournal.cluster(times, minSamples: 3), ClockTime(minuteOfDay: 10))
    }

    /// 次数够，但散在一天里，一小时之内凑不够三次：不猜。
    func testSpreadOutUnplugsAreNotLearned() {
        XCTAssertNil(HabitJournal.cluster([8 * 60, 12 * 60, 18 * 60, 22 * 60], minSamples: 3))
    }

    /// 两群人数一样多时取较早的那群，每次启动结果都要一样。
    func testTiedGroupsPickTheEarlierOne() {
        let morning = 10 * 60
        let evening = 20 * 60
        XCTAssertEqual(HabitJournal.cluster([morning, evening, morning, evening, morning, evening], minSamples: 3),
                       ClockTime(minuteOfDay: morning))
    }

    /// 学习进度：一共记下几次，一小时之内最多几次；最近记录从新到旧，带着日期。
    func testLearnProgressAndRecentUnplugs() {
        var journal = HabitJournal()
        journal.unplugMinutes = [23 * 60 + 30, 23 * 60 + 45]
        var monday = DayRecord(day: "2026-10-26")
        monday.unplug = 23 * 60 + 30
        var tuesday = DayRecord(day: "2026-10-27")
        tuesday.unplug = 23 * 60 + 45
        var quiet = DayRecord(day: "2026-10-28")
        quiet.unplug = nil
        journal.days = [monday, tuesday, quiet]

        let progress = journal.learnProgress()
        XCTAssertEqual(progress, LearnProgress(recorded: 2, bestCluster: 2))
        XCTAssertFalse(progress.learned)
        XCTAssertEqual(journal.recentUnplugs(5), [UnplugEvent(day: "2026-10-27", minute: 23 * 60 + 45),
                                                  UnplugEvent(day: "2026-10-26", minute: 23 * 60 + 30)])
    }

    /// 「够用」的一天：用电加接电合计 2 小时。少于这个不算数。
    func testUsableDaysCountsOnlyFullEnoughDays() {
        var journal = HabitJournal()
        var enough = DayRecord(day: "2026-10-27")
        enough.batteryMinutes = 90
        enough.powerMinutes = 60
        var short = DayRecord(day: "2026-10-28")
        short.batteryMinutes = 30
        journal.days = [enough, short]
        XCTAssertEqual(HabitTips.usableDays(journal: journal), 1)
    }

    /// 拔插只在当天第一次记，白天反复插拔不把习惯冲散。
    /// 每 5 分钟一个读数，按顺序一段一段接着喂，中间的插拔要能被看见。
    private func feed(_ journal: inout HabitJournal, _ segments: [(from: Int, to: Int, external: Bool)]) {
        var previous: ChargeSample?
        for segment in segments {
            for minute in stride(from: segment.from, to: segment.to, by: 5) {
                let current = sample(minute, percent: 90, external: segment.external)
                journal.absorb(current, previous: previous, day: "2026-10-29")
                previous = current
            }
        }
    }

    /// 接着电源满 30 分钟才算一次「离开电源」；当天只记第一次。
    func testFirstLongUnplugOnly() {
        var journal = HabitJournal()
        feed(&journal, [
            (540, 600, true),    // 9:00-10:00 接电，充了一小时
            (600, 605, false),   // 10:00 拔掉
            (605, 700, true),    // 挪回来又接上
            (700, 720, false),   // 又拔掉，但当天已经记过了
        ])
        let expected = HabitJournal.minuteOfDay(minutes(600))
        XCTAssertEqual(journal.today?.unplug, expected, "只认当天第一次")
        XCTAssertEqual(journal.unplugMinutes, [expected])
    }

    /// 接电不到 30 分钟就拔掉（挪个地方、插拔一下）不当作作息。
    func testShortSessionIsNotAnUnplug() {
        var journal = HabitJournal()
        feed(&journal, [(540, 560, true), (560, 600, false)])   // 只接了 20 分钟
        XCTAssertNil(journal.today?.unplug)
        XCTAssertTrue(journal.unplugMinutes.isEmpty, "短暂接电不记")
    }

    /// 两次读数隔了很久（程序没在跑）：不知道拔掉的确切时刻，不记。
    func testLongGapIsNotAnUnplug() {
        var journal = HabitJournal()
        journal.absorb(sample(540, percent: 90, external: true), previous: nil, day: "2026-10-29")
        journal.absorb(sample(540 + 180, percent: 90, external: false), previous: sample(540, percent: 90, external: true), day: "2026-10-29")
        XCTAssertTrue(journal.unplugMinutes.isEmpty, "三个小时的空档不算")
    }

    /// 重新学习：作息清掉，电量记录留着。
    func testForgetHabitsKeepsTheRest() {
        var journal = HabitJournal()
        feed(&journal, [(540, 600, true), (600, 605, false)])
        XCTAssertFalse(journal.unplugMinutes.isEmpty)
        journal.forgetHabits()
        XCTAssertTrue(journal.unplugMinutes.isEmpty)
        XCTAssertNil(journal.today?.unplug)
        XCTAssertNotNil(journal.today, "一天的汇总还在")
    }

    /// 换了新的一天就新开一行，旧的一天不续。
    func testNewDayStartsNewRow() {
        var journal = HabitJournal()
        let first = sample(0, percent: 80, external: true)
        journal.absorb(first, previous: nil, day: "2026-10-29")
        journal.absorb(sample(60, percent: 80, external: true), previous: first, day: "2026-10-30")
        XCTAssertEqual(journal.days.count, 2)
        XCTAssertEqual(journal.days.last?.day, "2026-10-30")
    }

    /// 时钟往回拨时不往新的一天乱写，也不删已有记录。
    func testClockGoingBackIsIgnored() {
        var journal = HabitJournal()
        let first = sample(0, percent: 80, external: true)
        journal.absorb(first, previous: nil, day: "2026-10-30")
        journal.absorb(sample(5, percent: 79, external: true), previous: first, day: "2026-10-29")
        XCTAssertEqual(journal.days.count, 1)
        XCTAssertEqual(journal.days.first?.day, "2026-10-30")
    }

    /// 记录只留 400 天。
    func testKeepsAboutAYear() {
        var journal = HabitJournal()
        var previous: ChargeSample?
        for day in 0..<(HabitJournal.keepDays + 20) {
            let value = ChargeSample(t: base.addingTimeInterval(Double(day) * 86_400), p: 80, c: false, x: true, l: 80)
            journal.absorb(value, previous: previous, day: String(format: "d%04d", day))
            previous = value
        }
        XCTAssertEqual(journal.days.count, HabitJournal.keepDays)
    }

    /// 挂满电的天数、平均用电池时长、最热温度。
    func testSummaryNumbers() {
        var journal = HabitJournal()
        for (index, full) in [600, 600, 60, 30].enumerated() {
            var record = DayRecord(day: "d\(index)")
            record.fullMinutes = Double(full)
            record.batteryMinutes = 120
            record.powerMinutes = 600
            record.celsiusSum = 30 * 10
            record.celsiusCount = 10
            record.hottest = 34 + Double(index)
            journal.days.append(record)
        }
        XCTAssertEqual(journal.daysFull(atLeast: 5, days: 7), 2)
        XCTAssertEqual(journal.averageBatteryHours(days: 7) ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(journal.hottest(days: 7), 37)
    }

    /// 存了再读，内容不变。
    func testRoundTrip() throws {
        var journal = HabitJournal()
        var record = DayRecord(day: "2026-10-29")
        record.lo = 40
        record.hi = 100
        record.cycles = 200
        journal.days.append(record)
        journal.unplugMinutes = [600]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try journal.save(to: url)
        XCTAssertEqual(HabitJournal.load(from: url), journal)
    }

    /// 文件坏了不能让程序读不出设置。
    func testBrokenFileGivesEmptyJournal() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-bad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{{ not json".utf8).write(to: url)
        XCTAssertEqual(HabitJournal.load(from: url), HabitJournal())
    }
}

final class HabitTipTests: XCTestCase {
    override func setUp() {
        super.setUp()
        pinChineseUI()
    }

    private func journal(fullMinutes: Int = 60, batteryMinutes: Int = 200, days: Int = 5, hottest: Double = 32) -> HabitJournal {
        var journal = HabitJournal()
        for index in 0..<days {
            var record = DayRecord(day: "d\(index)")
            record.fullMinutes = Double(fullMinutes)
            record.batteryMinutes = Double(batteryMinutes)
            record.powerMinutes = 600
            record.hottest = hottest
            record.cycles = 200 + index
            record.health = 93 - index
            journal.days.append(record)
        }
        return journal
    }

    /// 记录太少不说话。
    func testNeedsEnoughDays() {
        XCTAssertTrue(HabitTips.items(journal: journal(days: 2)).isEmpty, "两天不够")
    }

    /// 每天挂满电超过五小时，要提醒。
    func testFullTimeTip() {
        let tips = HabitTips.items(journal: journal(fullMinutes: 400))
        XCTAssertTrue(tips.contains { $0.kind == .fullTime })
    }

    /// 几乎不用电池的时候提醒，一天用两小时以上就不提。
    func testAlwaysPluggedTip() {
        XCTAssertTrue(HabitTips.items(journal: journal(batteryMinutes: 10)).contains { $0.kind == .alwaysPlugged })
        XCTAssertFalse(HabitTips.items(journal: journal(batteryMinutes: 120)).contains { $0.kind == .alwaysPlugged })
    }

    /// 温度高才提。
    func testHeatTip() {
        XCTAssertTrue(HabitTips.items(journal: journal(hottest: 41)).contains { $0.kind == .heat })
        XCTAssertFalse(HabitTips.items(journal: journal(hottest: 33)).contains { $0.kind == .heat })
    }

    /// 每一条都有非空的标题和说明，界面上不会出现空白行。
    func testTipsAreReadable() {
        var journal = journal(fullMinutes: 400, batteryMinutes: 5, hottest: 41)
        journal.unplugMinutes = [600, 601, 602]
        let tips = HabitTips.items(journal: journal)
        XCTAssertFalse(tips.isEmpty)
        for tip in tips {
            XCTAssertFalse(tip.title.isEmpty)
            XCTAssertFalse(tip.detail.isEmpty)
        }
    }
}
