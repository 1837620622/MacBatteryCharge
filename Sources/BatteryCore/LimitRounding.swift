import Foundation

/// 系统只接受它列出的几档充电上限（通常是 80、85、90、95、100）。要的值不在里面时，选离它最近的一档。
///
/// 平手时选低的那一档：宁可少充一点，也不要多充。
public enum LimitRounding {
    public static func nearestAccepted(_ limit: Int, choices: [Int]) -> Int {
        guard !choices.isEmpty, !choices.contains(limit) else { return limit }
        return choices.min { a, b in
            let distanceA = abs(a - limit)
            let distanceB = abs(b - limit)
            return distanceA == distanceB ? a < b : distanceA < distanceB
        } ?? limit
    }
}
