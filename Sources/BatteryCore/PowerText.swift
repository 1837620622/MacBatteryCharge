import Foundation

/// pmset 里低电量模式的两个值。有的机型叫 lowpowermode，有的叫 powermode（1 是低电量，2 是高性能）。
public struct LowPowerState: Equatable, Sendable {
    public var battery: Int
    public var ac: Int
    public var key: String

    public init(battery: Int, ac: Int, key: String = "lowpowermode") {
        self.battery = battery
        self.ac = ac
        self.key = key
    }

    public var batteryOn: Bool { battery == 1 }
    public var acOn: Bool { ac == 1 }

    /// 和三选一对得上时返回对应的选项。只在接电源时开，没有对应项。
    public var choice: LowPowerChoice? {
        switch (batteryOn, acOn) {
        case (false, false): return .off
        case (true, true): return .on
        case (true, false): return .battery
        default: return nil
        }
    }

    public func matches(_ choice: LowPowerChoice) -> Bool { self.choice == choice }

    public var text: String {
        if let choice { return choice.shortTitle }
        return "仅接电源"
    }

    /// 解析 `pmset -g custom`：要同时有 Battery Power 和 AC Power 两段。
    public static func parse(custom text: String) -> LowPowerState? {
        var section = ""
        var values: [String: [String: Int]] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Battery Power") { section = "battery"; continue }
            if line.hasPrefix("AC Power") { section = "ac"; continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard !section.isEmpty, fields.count >= 2, fields[0] == "lowpowermode" || fields[0] == "powermode",
                  let value = Int(fields[1]) else { continue }
            values[String(fields[0]), default: [:]][section] = value
        }
        for key in ["lowpowermode", "powermode"] {
            if let battery = values[key]?["battery"], let ac = values[key]?["ac"] {
                return LowPowerState(battery: battery, ac: ac, key: key)
            }
        }
        return nil
    }
}
