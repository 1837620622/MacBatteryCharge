import Foundation

/// 一天里的某一分钟，存成 "HH:mm"。
public struct ClockTime: Hashable, Comparable, Codable, Sendable {
    public private(set) var minuteOfDay: Int

    public init(minuteOfDay: Int) {
        self.minuteOfDay = ((minuteOfDay % 1440) + 1440) % 1440
    }

    public init(hour: Int, minute: Int) {
        self.init(minuteOfDay: hour * 60 + minute)
    }

    /// 只认 24 小时制的 "H:mm" 或 "HH:mm"。
    public init?(text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        for part in parts {
            guard (1...2).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        }
        guard let hour = Int(parts[0]), let minute = Int(parts[1]), hour <= 23, minute <= 59 else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var hour: Int { minuteOfDay / 60 }
    public var minute: Int { minuteOfDay % 60 }
    public var text: String { String(format: "%02d:%02d", hour, minute) }

    public func adding(minutes: Int) -> ClockTime { ClockTime(minuteOfDay: minuteOfDay + minutes) }

    /// 从 self 往后走到 other 要几分钟，0...1439。
    public func minutes(until other: ClockTime) -> Int {
        (other.minuteOfDay - minuteOfDay + 1440) % 1440
    }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool { lhs.minuteOfDay < rhs.minuteOfDay }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = ClockTime(text: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "时间要写成 HH:mm")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

/// 这一段的低电量模式。
public enum LowPowerChoice: String, CaseIterable, Codable, Sendable {
    case off
    case on
    case battery

    public var title: String {
        switch self {
        case .off: return "这段不用"
        case .on: return "这段一直开"
        case .battery: return "仅用电池时开"
        }
    }

    public var shortTitle: String {
        switch self {
        case .off: return "不用"
        case .on: return "一直开"
        case .battery: return "仅电池"
        }
    }

    /// pmset 的 -b（电池）和 -c（电源）两个值。
    public var modes: (battery: Int, ac: Int) {
        switch self {
        case .off: return (0, 0)
        case .on: return (1, 1)
        case .battery: return (1, 0)
        }
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        self = LowPowerChoice(rawValue: text) ?? .off
    }

    /// 不认识的写法按「不用」。
    public static func normalized(_ text: String?) -> LowPowerChoice {
        text.flatMap(LowPowerChoice.init(rawValue:)) ?? .off
    }
}

/// 一段时间：[start, end)。结束早于开始表示跨过午夜。
public struct Interval: Identifiable, Hashable, Codable, Sendable {
    public var id = UUID()
    public var start: ClockTime
    public var end: ClockTime
    public var limit: Int
    public var lowPower: LowPowerChoice
    /// 接着电源、电量高于上限时，先用电池放到上限再停住。要装放电帮手。
    public var discharge: Bool
    /// 漂移范围：0 为关。打开后，电量超过上限就放电，掉到 上限 − 范围 才接电，中间自己漂。
    public var drift: Int

    public init(start: ClockTime, end: ClockTime, limit: Int, lowPower: LowPowerChoice = .off, discharge: Bool = false, drift: Int = 0) {
        self.start = start
        self.end = end
        self.limit = limit
        self.lowPower = lowPower
        self.discharge = discharge
        self.drift = drift
    }

    enum CodingKeys: String, CodingKey {
        case start, end, limit, lowPower, discharge, drift
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(ClockTime.self, forKey: .start)
        end = try container.decode(ClockTime.self, forKey: .end)
        limit = try container.decode(Int.self, forKey: .limit)
        lowPower = (try? container.decodeIfPresent(LowPowerChoice.self, forKey: .lowPower)) ?? .off
        discharge = ((try? container.decodeIfPresent(Bool.self, forKey: .discharge)) ?? nil) ?? false
        drift = ((try? container.decodeIfPresent(Int.self, forKey: .drift)) ?? nil) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(limit, forKey: .limit)
        try container.encode(lowPower, forKey: .lowPower)
        try container.encode(discharge, forKey: .discharge)
        try container.encode(drift, forKey: .drift)
    }

    /// 漂移只在这一段放电时才有效，别的情况一律当作关。
    public static let driftChoices = [5, 10]
    public var activeDrift: Int {
        discharge && limit < 100 && Self.driftChoices.contains(drift) ? drift : 0
    }

    /// 放电时接电的电量。没有漂移就是上限本身。
    public var resumeAt: Int {
        activeDrift > 0 ? max(limit - activeDrift, ChargePolicy.dischargeFloor) : limit
    }

    public var length: Int { start.minutes(until: end) }
    public var wrapsMidnight: Bool { end.minuteOfDay < start.minuteOfDay }

    public func contains(_ minute: Int) -> Bool {
        let m = ClockTime(minuteOfDay: minute).minuteOfDay
        if start.minuteOfDay < end.minuteOfDay { return m >= start.minuteOfDay && m < end.minuteOfDay }
        return m >= start.minuteOfDay || m < end.minuteOfDay
    }

    public var rangeText: String {
        wrapsMidnight ? "\(start.text) – 次日 \(end.text)" : "\(start.text) – \(end.text)"
    }
}

public enum ScheduleError: Error, Equatable, Sendable {
    case tooMany
    case sameStartEnd(Int)
    case badLimit(Int)
    case overlap(Int, Int)

    public var message: String {
        switch self {
        case .tooMany: return "最多 \(Schedule.maxIntervals) 个时间段"
        case .sameStartEnd(let n): return "第 \(n) 段的开始和结束不能相同"
        case .badLimit(let n): return "第 \(n) 段的上限只能是 80、85、90、95 或 100"
        case .overlap(let a, let b): return "第 \(a) 段和第 \(b) 段有重叠"
        }
    }
}

/// 编译好的一天：每一分钟属于哪一段。空档按 100%。
public struct Schedule: Equatable, Sendable {
    public static let allowedLimits = [80, 85, 90, 95, 100]
    public static let maxIntervals = 12

    public let intervals: [Interval]
    private let owner: [Int]

    public static func compile(_ intervals: [Interval]) -> Result<Schedule, ScheduleError> {
        if intervals.count > maxIntervals { return .failure(.tooMany) }
        var owner = [Int](repeating: -1, count: 1440)
        for (index, item) in intervals.enumerated() {
            if item.start == item.end { return .failure(.sameStartEnd(index + 1)) }
            if !allowedLimits.contains(item.limit) { return .failure(.badLimit(index + 1)) }
            var cursor = item.start.minuteOfDay
            while cursor != item.end.minuteOfDay {
                if owner[cursor] != -1 { return .failure(.overlap(owner[cursor] + 1, index + 1)) }
                owner[cursor] = index
                cursor = (cursor + 1) % 1440
            }
        }
        return .success(Schedule(intervals: intervals, owner: owner))
    }

    /// 没排任何时间段时用：整天空档。
    public static let empty = Schedule(intervals: [], owner: [Int](repeating: -1, count: 1440))

    private init(intervals: [Interval], owner: [Int]) {
        self.intervals = intervals
        self.owner = owner
    }

    private func slot(_ minute: Int) -> Int { owner[ClockTime(minuteOfDay: minute).minuteOfDay] }

    public func interval(at minute: Int) -> Interval? {
        let index = slot(minute)
        return index >= 0 ? intervals[index] : nil
    }

    public func index(at minute: Int) -> Int? {
        let index = slot(minute)
        return index >= 0 ? index : nil
    }

    public func isGap(at minute: Int) -> Bool { slot(minute) < 0 }
    public func limit(at minute: Int) -> Int { interval(at: minute)?.limit ?? 100 }
    public func lowPower(at minute: Int) -> LowPowerChoice { interval(at: minute)?.lowPower ?? .off }
    public func discharge(at minute: Int) -> Bool { interval(at: minute)?.discharge ?? false }
    public func resumeAt(at minute: Int) -> Int { interval(at: minute)?.resumeAt ?? 100 }

    /// 窗口上的一句话：「06:00 起 80% · 21:00 起 100% · 23:30 断电」。
    public func dayLine(deadline: ClockTime?) -> String {
        var parts = intervals.sorted { $0.start < $1.start }.map { "\($0.start.text) 起 \($0.limit)%" }
        if let deadline { parts.append("\(deadline.text) 断电") }
        return parts.isEmpty ? "全天 100%" : parts.joined(separator: " · ")
    }

    public struct Change: Equatable, Sendable {
        public var minutesAhead: Int
        public var at: ClockTime
        public var limit: Int
    }

    /// 下一次上限变化。全天一个值时返回 nil。
    public func nextChange(after minute: Int) -> Change? {
        let now = limit(at: minute)
        for ahead in 1..<1440 where limit(at: minute + ahead) != now {
            return Change(minutesAhead: ahead, at: ClockTime(minuteOfDay: minute + ahead), limit: limit(at: minute + ahead))
        }
        return nil
    }

    /// 离开当前这一段（或空档）还有几分钟。
    public func minutesUntilBoundary(from minute: Int) -> Int? {
        let now = slot(minute)
        for ahead in 1..<1440 where slot(minute + ahead) != now { return ahead }
        return nil
    }

    /// 时间表条上用：连续的块，按时间顺序，从 00:00 开始。
    public struct Block: Equatable, Sendable {
        public var start: Int
        public var length: Int
        public var limit: Int
        public var index: Int?
    }

    public var blocks: [Block] {
        var result: [Block] = []
        var start = 0
        for minute in 1...1440 {
            if minute == 1440 || owner[minute] != owner[start] {
                let index = owner[start] >= 0 ? owner[start] : nil
                result.append(Block(start: start, length: minute - start, limit: limit(at: start), index: index))
                start = minute
            }
        }
        return result
    }

    /// 新加一段时，放在第一块空档里，最长 maxLength 分钟。一天排满时返回 nil。
    public static func firstFreeSlot(in intervals: [Interval], maxLength: Int = 60) -> (start: ClockTime, end: ClockTime)? {
        guard case .success(let schedule) = compile(intervals) else { return nil }
        if intervals.isEmpty {
            let start = ClockTime(hour: 6, minute: 0)
            return (start, start.adding(minutes: maxLength))
        }
        // 从某一段的结束点往后找，这样新段紧挨着已有的段。
        for item in intervals.sorted(by: { $0.end < $1.end }) {
            let start = item.end.minuteOfDay
            guard schedule.isGap(at: start) else { continue }
            var length = 0
            while length < maxLength && schedule.isGap(at: start + length) { length += 1 }
            return (ClockTime(minuteOfDay: start), ClockTime(minuteOfDay: start + length))
        }
        return nil
    }

    /// 06:00 来电后放到并停在 80%。21:00 放开到 100%，给 23:30 断电前留出约 2.5 小时。
    public static func makeDefaults() -> [Interval] {
        [
            Interval(start: ClockTime(hour: 6, minute: 0), end: ClockTime(hour: 21, minute: 0), limit: 80, lowPower: .off, discharge: true),
            Interval(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 6, minute: 0), limit: 100, lowPower: .battery),
        ]
    }
}

public func currentMinute(_ date: Date = Date(), calendar: Calendar = .current) -> Int {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
}
