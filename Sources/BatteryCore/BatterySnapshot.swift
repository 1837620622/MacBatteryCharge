import Foundation

/// 从 IOKit 字典里取数。数值可能是 Int、UInt64（负电流在 Apple 芯片上会变成 2^64 附近的无符号数）、NSNumber 或字符串。
public enum Reading {
    public static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as UInt64:
            return Int(truncatingIfNeeded: number)
        case let number as NSNumber:
            return Int(truncatingIfNeeded: number.int64Value)
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let number = Int(trimmed) { return number }
            if let number = UInt64(trimmed) { return Int(truncatingIfNeeded: number) }
            return nil
        default:
            return nil
        }
    }

    public static func flag(_ value: Any?) -> Bool? {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.intValue != 0
        case let text as String:
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "yes", "true", "1": return true
            case "no", "false", "0": return false
            default: return nil
            }
        default:
            return nil
        }
    }
}

public enum PowerFlow: Equatable, Sendable {
    case noBattery
    case charging
    case discharging
    case plugged
    case battery

    /// 菜单栏下排，四个字以内。
    public var menuWord: String {
        switch self {
        case .noBattery: return T("无电池")
        case .charging: return T("充电")
        case .discharging: return T("放电")
        case .plugged: return T("接通")
        case .battery: return T("电池")
        }
    }

    public var sentence: String {
        switch self {
        case .noBattery: return T("没有内置电池")
        case .charging: return T("正在充电")
        case .discharging: return T("正在放电")
        case .plugged: return T("电源直接供电")
        case .battery: return T("用电池")
        }
    }
}

public struct BatterySnapshot: Equatable, Sendable {
    public var present = false
    public var percent: Int?
    public var milliamps: Int?
    public var millivolts: Int?
    public var cycles: Int?
    public var designCycles: Int?
    public var designCapacity: Int?
    public var nominalCapacity: Int?
    public var rawMaxCapacity: Int?
    public var temperatureRaw: Int?
    public var isCharging = false
    public var externalConnected = false
    public var fullyCharged = false
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?
    public var adapterWatts: Int?
    public var thermallyLimited = false

    public init() {}

    /// registry 是 AppleSmartBattery 的属性；powerSource 是 IOPS 的内置电池描述；adapter 是 IOPSCopyExternalPowerAdapterDetails。
    public init(registry: [String: Any]?, powerSource: [String: Any]?, adapter: [String: Any]?) {
        let reg = registry ?? [:]
        let batteryData = reg["BatteryData"] as? [String: Any] ?? [:]
        let ps = powerSource ?? [:]

        func number(_ key: String) -> Int? {
            Reading.integer(reg[key]) ?? Reading.integer(batteryData[key])
        }

        let isInternal = (ps["Type"] as? String) == "InternalBattery"
        let installed = Reading.flag(reg["BatteryInstalled"])
        present = isInternal || (registry != nil && installed != false && (number("DesignCapacity") != nil || number("CurrentCapacity") != nil))

        // 电量优先用 IOPS，它已经换算成百分比。Intel 上 CurrentCapacity 是 mAh。
        if let current = Reading.integer(ps["Current Capacity"]), let maximum = Reading.integer(ps["Max Capacity"]), maximum > 0 {
            percent = Self.rounded(Double(current) * 100 / Double(maximum))
        } else if let current = number("CurrentCapacity"), let maximum = number("MaxCapacity"), maximum > 0 {
            percent = Self.rounded(Double(current) * 100 / Double(maximum))
        } else if let current = number("CurrentCapacity"), (0...100).contains(current) {
            percent = current
        }
        if let value = percent { percent = min(100, max(0, value)) }

        if let amps = number("InstantAmperage") ?? number("Amperage"), abs(amps) <= 30_000 {
            milliamps = amps
        }
        if let volts = number("Voltage"), volts > 0, volts < 30_000 { millivolts = volts }
        cycles = number("CycleCount")
        designCycles = number("DesignCycleCount9C") ?? number("DesignCycleCount")
        designCapacity = number("DesignCapacity")
        nominalCapacity = number("NominalChargeCapacity")
        rawMaxCapacity = number("AppleRawMaxCapacity")
        temperatureRaw = number("Temperature")
        thermallyLimited = (number("TimeChargingThermallyLimited") ?? 0) > 0

        isCharging = Reading.flag(reg["IsCharging"]) ?? Reading.flag(ps["Is Charging"]) ?? false
        externalConnected = Reading.flag(reg["ExternalConnected"]) ?? ((ps["Power Source State"] as? String) == "AC Power")
        fullyCharged = Reading.flag(reg["FullyCharged"]) ?? Reading.flag(ps["Is Charged"]) ?? false

        if !externalConnected { minutesToEmpty = Self.plausibleMinutes(ps["Time to Empty"]) }
        if externalConnected { minutesToFull = Self.plausibleMinutes(ps["Time to Full Charge"]) }
        if let watts = Reading.integer(adapter?["Watts"]), watts > 0 { adapterWatts = watts }
    }

    static func rounded(_ value: Double) -> Int { Int((value).rounded()) }

    /// 系统还算不出时间的时候，IOPS 给的是 65535（约 1092 小时）。那不是时间，当作没有；
    /// 超过一天的估计也不可信，同样不显示。
    static func plausibleMinutes(_ value: Any?) -> Int? {
        guard let minutes = Reading.integer(value), minutes > 0, minutes < 24 * 60 else { return nil }
        return minutes
    }

    /// 健康度：标称容量（没有时用满充容量）相对设计容量。
    public var health: Int? {
        guard let design = designCapacity, design > 0, let full = nominalCapacity ?? rawMaxCapacity, full > 0 else { return nil }
        return Self.rounded(Double(full) * 100 / Double(design))
    }

    /// Temperature 是百分之一度：3000 是 30.0°C。较旧的机器直接给整数度。
    public var celsius: Double? {
        guard let raw = temperatureRaw else { return nil }
        if (1000...6000).contains(raw) { return Double(raw) / 100 }
        if (0..<200).contains(raw) { return Double(raw) }
        return nil
    }

    /// 电池端的功率，正数是充进去，负数是放出来。
    public var watts: Double? {
        guard let mA = milliamps, let mV = millivolts else { return nil }
        return Double(mA) * Double(mV) / 1_000_000
    }

    public var flow: PowerFlow {
        if !present { return .noBattery }
        let current = milliamps ?? 0
        if isCharging || current > 50 { return .charging }
        if current < -50 { return .discharging }
        if externalConnected { return .plugged }
        return .battery
    }
}
