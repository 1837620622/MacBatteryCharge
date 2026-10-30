import Foundation

/// 软件怎么决定充到多少。三种模式回答的是三个不同的问题：
/// - `smart`：我只想随时有电，你看着办（护电池优先，其次保证电量）。
/// - `fixed`：我按作息排了时间表，照它执行。
/// - `full`：我不在乎，就一直给我充满。
public enum ChargeMode: String, Codable, CaseIterable, Sendable {
    case smart
    case fixed
    case full

    public var title: String {
        switch self {
        case .smart: return T("智能")
        case .fixed: return T("固定时间表")
        case .full: return T("一直充满")
        }
    }

    public var tagline: String {
        switch self {
        case .smart: return T("平时护电池，拔电源前自动补满")
        case .fixed: return T("按你排的时间段来，每段停在哪里你说了算")
        case .full: return T("接上电源就充满，适合台式机")
        }
    }

    public var detail: String {
        switch self {
        case .smart:
            return T("平时停在你选的数字（默认 80%），不一直满电。拔电源前按你平时的时间补到你要的量。不主动放电。")
        case .fixed:
            return T("每一段自己设上限，也能选放电。想完全自己控制就选这个。")
        case .full:
            return T("上限一直是 100%，接上电源就充满。护电池的好处最少，但拔了电源就是满的。")
        }
    }

    /// 只有固定模式能主动放电。智能模式放电会和「随时有电」冲突，一直充满也没有上限可放。
    public var allowsDischarge: Bool { self == .fixed }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        self = ChargeMode(rawValue: text) ?? .smart
    }

    public static func normalized(_ text: String?) -> ChargeMode {
        text.flatMap(ChargeMode.init(rawValue:)) ?? .smart
    }
}

/// 智能模式每一步的输入。
public struct SmartInput: Equatable, Sendable {
    public var percent: Int?
    public var external: Bool
    public var minute: Int
    /// 平时停在哪。默认 80%。
    public var dailyCap: Int
    /// 离电那一刻要多少。
    public var unplugTarget: Int
    /// 用户设的离电时间。
    public var deadline: ClockTime?
    /// 从历史里学出来的拔电源时间。有就用它，没有才用上面那个。
    public var learnedUnplug: ClockTime?
    public var rate: Double?
    public var heat: Bool
    public var topUp: Bool

    public init(percent: Int?, external: Bool, minute: Int, dailyCap: Int = SmartPolicy.defaultDailyCap,
                unplugTarget: Int = ChargePlanner.defaultTarget, deadline: ClockTime? = nil,
                learnedUnplug: ClockTime? = nil, rate: Double? = nil, heat: Bool = false, topUp: Bool = false) {
        self.percent = percent
        self.external = external
        self.minute = minute
        self.dailyCap = dailyCap
        self.unplugTarget = unplugTarget
        self.deadline = deadline
        self.learnedUnplug = learnedUnplug
        self.rate = rate
        self.heat = heat
        self.topUp = topUp
    }
}

public struct SmartDecision: Equatable, Sendable {
    public var decision: LimitDecision
    /// 这次按哪个离电时间算的。
    public var deadline: ClockTime?
    /// 用的是学出来的时间，不是用户设的。
    public var learned: Bool
    /// 离电计划。太远时不给，因为那时候算出来的时间会一直变。
    public var plan: ChargePlan?
    /// 平时停在哪。
    public var cap: Int

    public init(decision: LimitDecision, deadline: ClockTime?, learned: Bool, plan: ChargePlan?, cap: Int) {
        self.decision = decision
        self.deadline = deadline
        self.learned = learned
        self.plan = plan
        self.cap = cap
    }
}

/// 智能模式：护电池优先，其次保证离电时够用。
///
/// 规则只有三条，都能在窗口里说清楚：
/// 1. 平时停在日常上限，不主动放电，也不为了「准备」去耗电。
/// 2. 按离电时间反推最晚什么时候放开；到了那一刻就放开到离电目标。只往高放，不往低收。
/// 3. 电池偏热时最高 80%，热的时候不为了满电硬充。
public enum SmartPolicy {
    /// 日常上限的常用档位。档位之外可以自定义，范围见 `dailyCapRange`。100 不在这里：要 100 请用「一直充满」。
    public static let dailyCapChoices = [80, 85, 90, 95]
    public static let dailyCapRange = 50...95
    public static let defaultDailyCap = 80
    /// 离电时间往前看多久。超过这个时间就不给预计，因为太早的估计没有意义。
    public static let window = 480

    /// 只夹到范围里，不再吸附到档位：填 83 就是 83。
    public static func clampDailyCap(_ value: Int) -> Int {
        min(dailyCapRange.upperBound, max(dailyCapRange.lowerBound, value))
    }

    /// 预测里用的时间表：整天停在 `cap`。拼成两段，中间没有空档，免得空档被当成 100%。
    public static func flatSchedule(cap: Int) -> Schedule {
        let halves = [
            Interval(start: ClockTime(hour: 0, minute: 0), end: ClockTime(hour: 12, minute: 0), limit: cap),
            Interval(start: ClockTime(hour: 12, minute: 0), end: ClockTime(hour: 0, minute: 0), limit: cap),
        ]
        return (try? Schedule.compile(halves).get()) ?? .empty
    }

    public static func decide(_ input: SmartInput) -> SmartDecision {
        let cap = clampDailyCap(input.dailyCap)
        let target = ChargePlanner.clampTarget(input.unplugTarget)
        let deadline = input.learnedUnplug ?? input.deadline
        let learned = input.learnedUnplug != nil

        var plan: ChargePlan?
        if let deadline, let percent = input.percent {
            plan = ChargePlanner.plan(minute: input.minute, percent: percent, deadline: deadline,
                                      target: target, base: cap, rate: input.rate,
                                      window: window)
        }

        var limit = cap
        var reason: LimitReason = .smart
        // 只往上放：已经有更高的临时上限（比如临时充满）时不在这里降下来。
        if let plan, plan.liftNow, target > limit {
            limit = target
            reason = .deadline
        }
        if input.topUp && limit < 100 {
            limit = 100
            reason = .topUp
        }
        // 热的时候不去追满电，这是唯一会往下压的一条。
        if input.heat && limit > 80 {
            limit = 80
            reason = .heat
        }
        return SmartDecision(decision: LimitDecision(limit: limit, reason: reason, scheduled: cap),
                             deadline: deadline, learned: learned, plan: plan, cap: cap)
    }

    /// 窗口里那句「现在在做什么」。
    public static func explain(_ value: SmartDecision, target: Int) -> String {
        switch value.decision.reason {
        case .heat:
            return T("电池偏热，先停在 80%")
        case .topUp:
            return T("临时充满到 100%")
        case .deadline:
            let at = value.deadline?.display ?? T("离电")
            return T("为 %@ 拔电源做准备，补到 %@%", ["\(at)", "\(value.decision.limit)"])
        default:
            if let plan = value.plan, plan.minutesNeeded == 0 {
                return T("已经补到 %@%，停在 %@% 不动", ["\(target)", "\(value.cap)"])
            }
            return T("平时停在 %@%，拔电源前会补满", ["\(value.cap)"])
        }
    }
}
