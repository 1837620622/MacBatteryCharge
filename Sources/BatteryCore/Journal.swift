import Foundation

/// 一天一行，像健康 App 的日汇总。
///
/// 只存汇总，不存每秒的原始样本：一个文件记一年也只有几百行，
/// 打开窗口时不用为了画一张图去读几十万个点。
public struct DayRecord: Codable, Equatable, Sendable {
    /// yyyy-MM-dd，本机时区。
    public var day: String
    /// 当天最低、最高电量。
    public var lo: Int?
    public var hi: Int?
    /// 用电池的分钟数。读数可能每 30 秒一次，所以存小数，不能每次取整。
    public var batteryMinutes: Double = 0
    /// 接着电源的分钟数。
    public var powerMinutes: Double = 0
    /// 接着电源、电量 ≥ 99% 的分钟数。用来发现「一直挂满」。
    public var fullMinutes: Double = 0
    /// 当天第一次拔电源的时刻（一天内的第几分钟）。一天只记第一次。
    public var unplug: Int?
    /// 当天第一次接回电源的时刻。
    public var plug: Int?
    /// 当天最热、平均温度。
    public var hottest: Double?
    public var celsiusSum: Double = 0
    public var celsiusCount: Int = 0
    public var cycles: Int?
    public var health: Int?

    public init(day: String) { self.day = day }

    public var averageCelsius: Double? {
        celsiusCount > 0 ? celsiusSum / Double(celsiusCount) : nil
    }

    /// 一天里有多少小时是挂满电的。
    public var fullHours: Double { Double(fullMinutes) / 60 }

    /// 一天里有多少小时在用电池。
    public var batteryHours: Double { Double(batteryMinutes) / 60 }
    /// 一天里有多少小时接着电源。
    public var powerHours: Double { Double(powerMinutes) / 60 }
}

/// 长期记录。比 `ChargeHistory`（只留 72 小时）长得多，是「习惯」的来源。
///
/// 每个读数进来时调一次 `absorb`，一天一行累加。文件写 `journal.json`，
/// 和设置分开，坏了也不影响设置。
public struct HabitJournal: Codable, Equatable, Sendable {
    public static let keepDays = 400
    /// 单次间隔超过这个就当作程序没在跑，不计入时长。
    public static let maxGapMinutes = 30

    public var days: [DayRecord] = []
    /// 最近拔电源的时刻（一天内的第几分钟），最多留这么多条。
    public var unplugMinutes: [Int] = []
    public var plugMinutes: [Int] = []
    /// 这次接上电源的时刻。拔掉时用它算充了多久；没接着电源时是 nil。
    public var pluggedSince: Date?
    /// 接着电源满这么多分钟，拔掉才算一次「离开电源」。短暂拔下来挪个地方不算作息。
    public static let minPluggedMinutes = 30
    /// 至少记下这么多次「离开电源」，才开始说「平时几点拔」。
    public static let minLearnCount = 3

    public init() {}

    public var today: DayRecord? { days.last }

    /// 记一个读数。`previous` 是上一次的读数，用来算时长和判断插拔。
    public mutating func absorb(_ sample: ChargeSample, previous: ChargeSample?, day: String,
                               celsius: Double? = nil, cycles: Int? = nil, health: Int? = nil) {
        let index: Int
        if let last = days.last, last.day == day {
            index = days.count - 1
        } else if let last = days.last, day < last.day {
            // 时钟被往回调了，忽略这一条，不要把旧的一天续到新的一天上。
            return
        } else {
            days.append(DayRecord(day: day))
            // 先裁掉最老的，再取下标：裁完再算，否则下标会落在数组尾巴外面。
            if days.count > Self.keepDays { days.removeFirst(days.count - Self.keepDays) }
            index = days.count - 1
        }

        if let previous {
            // 不取整：读数每 30 秒一次的时候，每一段都不满一分钟，取整会全部变成 0。
            let minutes = sample.t.timeIntervalSince(previous.t) / 60
            if minutes > 0 && minutes <= Double(Self.maxGapMinutes) {
                // 按上一个读数之后的那段状态计：那段时间里机器是什么状态，上一读数说了算。
                if previous.x {
                    days[index].powerMinutes += minutes
                    if previous.p >= 99 { days[index].fullMinutes += minutes }
                } else {
                    days[index].batteryMinutes += minutes
                }
            }
        }

        days[index].lo = days[index].lo.map { min($0, sample.p) } ?? sample.p
        days[index].hi = days[index].hi.map { max($0, sample.p) } ?? sample.p
        if let celsius {
            days[index].hottest = days[index].hottest.map { max($0, celsius) } ?? celsius
            days[index].celsiusSum += celsius
            days[index].celsiusCount += 1
        }
        if let cycles { days[index].cycles = cycles }
        if let health { days[index].health = health }

        // 两次读数隔得太久（程序没在跑）时，插拔的确切时刻不知道，不记时刻，只把接电的起点重置。
        let gap = previous.map { sample.t.timeIntervalSince($0.t) / 60 } ?? .infinity
        let continuous = gap > 0 && gap <= Double(Self.maxGapMinutes)
        let wasPlugged = previous?.x ?? false
        let ofDay = Self.minuteOfDay(sample.t)

        if sample.x && !wasPlugged {
            pluggedSince = sample.t
            // 只记当天第一次接上，和第一次拔掉一样。
            if continuous && days[index].plug == nil {
                days[index].plug = ofDay
                plugMinutes.append(ofDay)
                if plugMinutes.count > 120 { plugMinutes.removeFirst(plugMinutes.count - 120) }
            }
        }
        if !sample.x && wasPlugged {
            let charged = pluggedSince.map { sample.t.timeIntervalSince($0) / 60 } ?? 0
            pluggedSince = nil
            // 只有接着电源满 minPluggedMinutes 分钟、并且是当天第一次，才算一次「离开电源」。
            // 白天挪个地方、插拔一下，不当作作息，免得把习惯冲成噪声。
            if continuous && charged >= Double(Self.minPluggedMinutes) && days[index].unplug == nil {
                days[index].unplug = ofDay
                unplugMinutes.append(ofDay)
                if unplugMinutes.count > 120 { unplugMinutes.removeFirst(unplugMinutes.count - 120) }
            }
        }
    }

    /// 清掉学到的作息，从头学。电量曲线和长期记录的其它部分不动。
    public mutating func forgetHabits() {
        unplugMinutes = []
        plugMinutes = []
        for index in days.indices {
            days[index].unplug = nil
            days[index].plug = nil
        }
    }

    public static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// 从长期记录里学「平时几点拔电源」。和 `ChargeHistory.learnedUnplug` 同一套投票，
    /// 但用的是几个月的记录，不是 72 小时。至少要有 `minSamples` 次，否则不猜。
    public func learnedUnplug(minSamples: Int = HabitJournal.minLearnCount) -> ClockTime? {
        Self.vote(unplugMinutes, minSamples: minSamples)
    }

    public func learnedPlug(minSamples: Int = 3) -> ClockTime? {
        Self.vote(plugMinutes, minSamples: minSamples)
    }

    /// 按 30 分钟一档投票，取票数最多那一档里出现最多的时刻。并列时取最早的。
    static func vote(_ values: [Int], minSamples: Int) -> ClockTime? {
        guard values.count >= minSamples else { return nil }
        var buckets: [Int: [Int]] = [:]
        for value in values { buckets[value / 30, default: []].append(value) }
        // 票数一样多时取较早的一档。字典的遍历顺序每次启动都不一样，不能直接取「第一个」。
        guard let best = buckets.max(by: { a, b in a.value.count == b.value.count ? a.key > b.key : a.value.count < b.value.count }),
              best.value.count >= minSamples else {
            return nil
        }
        var counts: [Int: Int] = [:]
        for value in best.value { counts[value, default: 0] += 1 }
        let top = counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }
        return top.map { ClockTime(minuteOfDay: $0.key) }
    }

    public func daysBack(_ count: Int) -> [DayRecord] {
        Array(days.suffix(count))
    }

    /// 最近这些天里，健康度变化了多少（百分点）。不足两天返回 nil。
    public func healthChange(days count: Int = 30) -> Int? {
        let points = daysBack(count).compactMap(\.health)
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        return last - first
    }

    /// 最近这些天平均每天用电池多少小时。
    public func averageBatteryHours(days count: Int = 7) -> Double? {
        let records = daysBack(count).filter { $0.batteryMinutes + $0.powerMinutes > 60 }
        guard !records.isEmpty else { return nil }
        return records.reduce(0) { $0 + $1.batteryHours } / Double(records.count)
    }

    /// 最近这些天里，有几天挂满电超过 `hours` 小时。
    public func daysFull(atLeast hours: Double, days count: Int = 7) -> Int {
        daysBack(count).filter { $0.fullHours >= hours }.count
    }

    public func hottest(days count: Int = 7) -> Double? {
        daysBack(count).compactMap(\.hottest).max()
    }

    public static func load(from url: URL) -> HabitJournal {
        guard let data = try? Data(contentsOf: url) else { return HabitJournal() }
        return (try? JSONDecoder().decode(HabitJournal.self, from: data)) ?? HabitJournal()
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
