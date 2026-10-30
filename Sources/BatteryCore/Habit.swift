import Foundation

/// 一条温馨提醒。只在记录够多的时候才出现，不猜。
public struct HabitTip: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// 长期挂满电。
        case fullTime
        /// 学出了拔电源的时间。
        case unplugPattern
        /// 几乎不用电池。
        case alwaysPlugged
        /// 温度偏高。
        case heat
        /// 健康度在掉。
        case health
        /// 循环次数涨得快。
        case cycles

        public var id: String { rawValue }
    }

    public var kind: Kind
    public var symbol: String
    public var title: String
    public var detail: String

    public var id: String { kind.rawValue }

    public init(_ kind: Kind, _ symbol: String, _ title: String, _ detail: String) {
        self.kind = kind
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}

/// 从长期记录里读几句话出来。每一条都对应一个数字，不写「建议您注意电池健康」这种空话。
public enum HabitTips {
    /// 至少这么多天有足够记录才开口，否则样本太少。
    public static let minDays = 3

    public static func items(journal: HabitJournal, calendar: Calendar = .current) -> [HabitTip] {
        let recent = journal.daysBack(7).filter { $0.batteryMinutes + $0.powerMinutes >= 120 }
        guard recent.count >= minDays else { return [] }
        var tips: [HabitTip] = []

        // 一直挂满：护电池最实际的一条。
        let fullDays = recent.filter { $0.fullHours >= 5 }.count
        if fullDays >= 3 {
            tips.append(HabitTip(.fullTime, "battery.100.bolt",
                                 T("这一周有 %@ 天挂在满电", ["\(fullDays)"]),
                                 T("满电放着最伤电池。把日常上限降到 80%，要出门前它会自己补到 100%。")))
        }

        // 学出来的拔电时间。
        if let unplug = journal.learnedUnplug() {
            tips.append(HabitTip(.unplugPattern, "clock.arrow.circlepath",
                                 T("你平时大约 %@ 拔电源", ["\(unplug.display)"]),
                                 T("到点前我会先备好电，不用你自己盯着。")))
        }

        // 几乎不用电池。
        if recent.allSatisfy({ $0.batteryHours < 0.5 }) {
            tips.append(HabitTip(.alwaysPlugged, "powerplug.fill",
                                 T("这一周几乎一直插着电源"),
                                 T("一直插着电源时，电池长时间停在高电量最伤电池。日常上限设在 80%，比一直满电好。")))
        }

        // 温度。
        if let hottest = journal.hottest(days: 7), hottest >= 38 {
            tips.append(HabitTip(.heat, "thermometer.high",
                                 T("这一周最热到 %@", [String(format: "%.0f°C", hottest)]),
                                 T("充电时温度高最伤电池。别在被子上或太阳底下充电，过热保护会先停在 80%。")))
        }

        // 健康度变化。
        if let change = journal.healthChange(days: 30), change <= -2 {
            tips.append(HabitTip(.health, "heart.slash",
                                 T("这 30 天健康度掉了 %@ 个点", ["\(-change)"]),
                                 T("掉得快多半和高温、长时间满电有关。可以先看上面两条。")))
        }

        // 循环次数。
        let cycles = recent.compactMap(\.cycles)
        if let first = cycles.first, let last = cycles.last, cycles.count >= 3, last - first >= 15 {
            tips.append(HabitTip(.cycles, "arrow.triangle.2.circlepath",
                                 T("这 7 天用了 %@ 次循环", ["\(last - first)"]),
                                 T("一天一个循环左右是正常的。如果明显更多，说明电池在反复充放。")))
        }

        return tips
    }
}
