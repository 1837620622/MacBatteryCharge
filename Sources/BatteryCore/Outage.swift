import Foundation

/// 工作日停电：住宿舍时，周一到周五的晚上停电，早上来电；周末在家，全天有电。
/// 停电算在开始那一天：周一 23:30 到周二 06:00 都是周一的停电。
public enum Outage {
    /// 日历里的星期：1 是周日，2 到 6 是周一到周五。
    public static func isWorkday(weekday: Int) -> Bool {
        (2...6).contains(weekday)
    }

    /// 这一刻是不是在停电里。`minute` 是一天里的分钟，`weekday` 用日历的写法（1 是周日）。
    /// 开始和结束在同一天之内（比如 01:00 到 06:00）时，只看今天；跨过午夜时，凌晨那一段算前一天的停电。
    public static func isOut(minute: Int, weekday: Int, start: ClockTime, end: ClockTime) -> Bool {
        let from = start.minuteOfDay
        let to = end.minuteOfDay
        if from == to { return false }
        if from < to {
            return minute >= from && minute < to && isWorkday(weekday: weekday)
        }
        if minute >= from { return isWorkday(weekday: weekday) }
        if minute < to { return isWorkday(weekday: weekday == 1 ? 7 : weekday - 1) }
        return false
    }

    /// 停电时低电量模式该是什么。停电中、并且用户勾了「停电时保持低电量」，就开；
    /// 其余时候只关掉自己开过的（`wereOn`），没开过就不碰（nil），用户手动设的不动。
    public static func lowPowerWanted(cutNow: Bool, keep: Bool, wereOn: Bool) -> Bool? {
        if cutNow && keep { return true }
        return wereOn ? false : nil
    }
}
