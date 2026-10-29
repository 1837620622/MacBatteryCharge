import Foundation

/// 现在写给系统的上限是怎么来的。
public enum LimitReason: Equatable, Sendable {
    case schedule
    case gap
    case topUp
    case deadline
    case heat

    public var title: String {
        switch self {
        case .schedule: return "按时间表"
        case .gap: return "空档按 100%"
        case .topUp: return "临时充满"
        case .deadline: return "断电前充满"
        case .heat: return "过热保护"
        }
    }
}

public struct LimitDecision: Equatable, Sendable {
    public var limit: Int
    public var reason: LimitReason
    /// 时间表本来的值。
    public var scheduled: Int

    public init(limit: Int, reason: LimitReason, scheduled: Int) {
        self.limit = limit
        self.reason = reason
        self.scheduled = scheduled
    }
}

public enum ChargePolicy {
    /// 断电前充满和临时充满只会往上放；过热保护最后压到 80。放电另由 shouldDischarge 决定。
    public static func decide(schedule: Schedule, minute: Int, topUp: Bool, deadlineLift: Int?, heat: Bool) -> LimitDecision {
        let scheduled = schedule.limit(at: minute)
        var decision = LimitDecision(limit: scheduled, reason: schedule.isGap(at: minute) ? .gap : .schedule, scheduled: scheduled)
        if let lift = deadlineLift, lift > decision.limit {
            decision.limit = lift
            decision.reason = .deadline
        }
        if topUp && decision.limit < 100 {
            decision.limit = 100
            decision.reason = .topUp
        }
        if heat && decision.limit > 80 {
            decision.limit = 80
            decision.reason = .heat
        }
        return decision
    }

    /// 放电最低到这里。低于它就不再断开电源，帮手那边也守着同一个下限（Calma 也是 20%）。
    public static let dischargeFloor = 20
    /// 没有漂移时，电量要超过上限这么多才开始放。苹果的上限会停在“几个百分点”之内，
    /// 留出这一段，免得 80 和 82 之间反复放、反复充。
    public static let dischargeMargin = 3
    /// 电池温度超过 35°C 就停止往上充，降到 33°C 才恢复。35 和 33 是我们选的保守值，不是苹果规定的电池温度。
    public static let heatOn = 35.0
    public static let heatOff = 33.0

    /// 开始放的电量和停下接电的电量。没有漂移：超过上限 dischargeMargin 才开始，放到上限就接电。
    /// 有漂移：到上限就开始，掉到 resumeAt 才接电，电量就在两者之间漂。
    public static func dischargeWindow(limit: Int, resumeAt: Int) -> (start: Int, resume: Int) {
        let resume = max(min(resumeAt, limit), dischargeFloor)
        let start = resume < limit ? limit : limit + dischargeMargin
        return (start, resume)
    }

    /// 这一段开着放电、接着电源（包括帮手已经断开电源）时才放。过热保护、临时充满、断电前充满、空档都不放。
    public static func shouldDischarge(previous: Bool, percent: Int?, decision: LimitDecision,
                                       enabled: Bool, external: Bool, resumeAt: Int? = nil) -> Bool {
        guard enabled, external, let percent, decision.reason == .schedule, decision.limit < 100 else { return false }
        let window = dischargeWindow(limit: decision.limit, resumeAt: resumeAt ?? decision.limit)
        if percent <= dischargeFloor { return false }
        return previous ? percent > window.resume : percent >= window.start
    }

    /// 超过 35°C 开始保护，降到 33°C 以下才解除，中间保持上一次的状态，免得来回跳。
    public static func heatActive(previous: Bool, celsius: Double?, external: Bool) -> Bool {
        guard external, let celsius else { return false }
        if celsius >= heatOn { return true }
        if celsius <= heatOff { return false }
        return previous
    }
}

public struct ChargePlan: Equatable, Sendable {
    /// 时间表在断电前一分钟要的上限。
    public var target: Int
    public var minutesToDeadline: Int
    /// 按充电速度，从现在的电量充到 target 要几分钟。
    public var minutesNeeded: Int
    /// 时间表放开之前就得先放开。
    public var liftNow: Bool
    /// 从现在起几分钟后到 target；已经够了是 0。
    public var etaMinutes: Int
    public var rate: Double
    public var learned: Bool

    public var reachesInTime: Bool { etaMinutes <= minutesToDeadline }
}

public enum ChargePlanner {
    /// 80% 到 100% 这一段的保守速度，大约一小时 20%。
    public static let defaultRate = 0.33

    /// 只看断电前 window 分钟以内。只会比时间表更早放开，不会更晚。
    public static func plan(schedule: Schedule, minute: Int, percent: Int, deadline: ClockTime,
                            rate learnedRate: Double?, margin: Int = 15, window: Int = 480) -> ChargePlan? {
        let toDeadline = ClockTime(minuteOfDay: minute).minutes(until: deadline)
        guard toDeadline > 0, toDeadline <= window else { return nil }
        let target = schedule.limit(at: deadline.minuteOfDay - 1)
        let rate = max(0.05, min(3, learnedRate ?? defaultRate))
        let need = max(0, target - percent)
        let needed = need == 0 ? 0 : Int((Double(need) / rate).rounded(.up))

        if need == 0 || schedule.limit(at: minute) >= target {
            return ChargePlan(target: target, minutesToDeadline: toDeadline, minutesNeeded: needed,
                              liftNow: false, etaMinutes: needed, rate: rate, learned: learnedRate != nil)
        }
        // 时间表在断电前什么时候放开到 target。
        var scheduledLift = toDeadline
        for ahead in 1..<toDeadline where schedule.limit(at: minute + ahead) >= target {
            scheduledLift = ahead
            break
        }
        let latestStart = toDeadline - needed - margin
        let start = max(0, min(scheduledLift, latestStart))
        return ChargePlan(target: target, minutesToDeadline: toDeadline, minutesNeeded: needed,
                          liftNow: latestStart <= 0, etaMinutes: start + needed, rate: rate, learned: learnedRate != nil)
    }
}
