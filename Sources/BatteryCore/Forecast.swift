import Foundation

public struct ForecastPoint: Equatable, Sendable {
    public var minutesAhead: Int
    public var percent: Double
    public var charging: Bool
    public var discharging: Bool

    public init(minutesAhead: Int, percent: Double, charging: Bool, discharging: Bool) {
        self.minutesAhead = minutesAhead
        self.percent = percent
        self.charging = charging
        self.discharging = discharging
    }
}

/// 按时间表、断电前充满和放电，把接下来几个小时的电量走一遍，画在曲线后面做虚线。
public enum Forecast {
    /// 接着电源放电时，整机一般每小时用掉 10% 左右。
    public static let defaultDrainRate = 0.17

    public static func points(schedule: Schedule, minute: Int, percent: Int, external: Bool,
                              deadline: ClockTime?, target: Int = ChargePlanner.defaultTarget,
                              chargeRate: Double?, drainRate: Double = defaultDrainRate,
                              dischargeAvailable: Bool, topUpMinutes: Int? = nil,
                              horizon: Int = 720, step: Int = 5) -> [ForecastPoint] {
        let rate = max(0.05, min(3, chargeRate ?? ChargePlanner.defaultRate))
        let drain = max(0.02, min(2, drainRate))
        let toDeadline = deadline.map { ClockTime(minuteOfDay: minute).minutes(until: $0) }
        let end = min(horizon, toDeadline.map { $0 == 0 ? horizon : $0 } ?? horizon)

        var p = Double(percent)
        var lift: Int?
        var discharging = false
        var result = [ForecastPoint(minutesAhead: 0, percent: p, charging: false, discharging: false)]
        var ahead = 0
        while ahead < end {
            let now = minute + ahead
            if let deadline, external, lift == nil,
               let plan = ChargePlanner.plan(schedule: schedule, minute: now, percent: Int(p.rounded(.down)),
                                             deadline: deadline, target: target, rate: rate), plan.liftNow {
                lift = plan.target
            }
            let topUp = topUpMinutes.map { ahead < $0 } ?? false
            let decision = ChargePolicy.decide(schedule: schedule, minute: now, topUp: topUp, deadlineLift: lift, heat: false)
            discharging = ChargePolicy.shouldDischarge(previous: discharging, percent: Int(p.rounded()), decision: decision,
                                                       enabled: dischargeAvailable && schedule.discharge(at: now),
                                                       external: external, resumeAt: schedule.resumeAt(at: now))
            let span = Double(min(step, end - ahead))
            var charging = false
            if !external {
                p = max(0, p - drain * span)
            } else if discharging {
                p = max(Double(schedule.resumeAt(at: now)), p - drain * span)
            } else if p < Double(decision.limit) {
                p = min(Double(decision.limit), p + rate * span)
                charging = true
            }
            ahead += Int(span)
            result.append(ForecastPoint(minutesAhead: ahead, percent: p, charging: charging, discharging: discharging))
        }
        return result
    }
}
