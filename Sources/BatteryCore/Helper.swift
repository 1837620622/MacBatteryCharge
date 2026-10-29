import Foundation

/// 放电帮手：一个以 root 运行的系统后台程序，只做三件事：
/// 断开或接回电源适配器（接着电源也用电池），在旧系统上停止或恢复充电，报告状态。
/// 程序和它之间走本机的 Unix 套接字，一行 JSON 一问一答。
public enum HelperInfo {
    public static let label = "com.macbatterycharge.helper"
    public static let socketPath = "/var/run/com.macbatterycharge.helper.sock"
    public static let installedBinary = "/Library/PrivilegedHelperTools/com.macbatterycharge.helper"
    public static let launchDaemonPlist = "/Library/LaunchDaemons/com.macbatterycharge.helper.plist"
    /// 帮手协议版本。和程序不一致时要重新装帮手。
    public static let protocolVersion = 1
    /// 程序隔一会儿就续一次。帮手超过这个时间没收到，就自己接回电源，程序崩了也不会一直放下去。
    public static let maxLease = 300
}

public struct HelperRequest: Codable, Equatable, Sendable {
    public enum Command: String, Codable, Sendable {
        case status
        case apply
        /// 卸载前用：接回电源、恢复充电、忘掉上限。
        case reset
    }

    public var cmd: Command
    /// 只在系统没有原生充电上限、帮手能直接停充时才带。nil 表示帮手不管上限。
    public var limit: Int?
    /// 放电到这里为止。nil 表示不放电。
    public var dischargeTo: Int?
    /// 放电指令有效几秒。
    public var lease: Int?

    public init(cmd: Command, limit: Int? = nil, dischargeTo: Int? = nil, lease: Int? = nil) {
        self.cmd = cmd
        self.limit = limit
        self.dischargeTo = dischargeTo
        self.lease = lease
    }
}

/// 帮手能用哪种方式停止充电。
public enum HelperChargeControl: String, Codable, Sendable {
    /// CH0B/CH0C 或 CHTE，直接停充。
    case direct
    /// 新固件：充电上限由系统自己管，帮手不碰。
    case system
    case none
}

public struct HelperStatus: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var version: String
    public var adapterControl: Bool
    public var chargeControl: HelperChargeControl
    /// 电源适配器现在是不是接通的（SMC 层面）。false 表示正在用电池放电。
    public var adapterEnabled: Bool?
    public var chargingEnabled: Bool?
    public var percent: Int?
    public var external: Bool
    public var limit: Int?
    public var dischargeTo: Int?
    /// 放电指令还剩几秒。
    public var leaseRemaining: Int
    public var sleeping: Bool
    public var error: String?

    public init(protocolVersion: Int = HelperInfo.protocolVersion, version: String, adapterControl: Bool,
                chargeControl: HelperChargeControl, adapterEnabled: Bool? = nil, chargingEnabled: Bool? = nil,
                percent: Int? = nil, external: Bool = false, limit: Int? = nil, dischargeTo: Int? = nil,
                leaseRemaining: Int = 0, sleeping: Bool = false, error: String? = nil) {
        self.protocolVersion = protocolVersion
        self.version = version
        self.adapterControl = adapterControl
        self.chargeControl = chargeControl
        self.adapterEnabled = adapterEnabled
        self.chargingEnabled = chargingEnabled
        self.percent = percent
        self.external = external
        self.limit = limit
        self.dischargeTo = dischargeTo
        self.leaseRemaining = leaseRemaining
        self.sleeping = sleeping
        self.error = error
    }

    /// 正在接着电源用电池。
    public var discharging: Bool { adapterEnabled == false && external }
}

/// 帮手每 10 秒、每次收到指令、睡眠前后都按这个算一遍。纯函数，方便测试。
public enum HelperPolicy {
    public struct Input: Equatable, Sendable {
        public var percent: Int?
        public var external: Bool
        public var sleeping: Bool
        public var limit: Int?
        public var dischargeTo: Int?
        public var leaseValid: Bool
        public var chargingBefore: Bool
        /// 电源适配器现在是不是被帮手断开着。断开后系统会说“没接电源”，所以这时不能再看 external。
        public var adapterDisabled: Bool

        public init(percent: Int?, external: Bool, sleeping: Bool, limit: Int?, dischargeTo: Int?,
                    leaseValid: Bool, chargingBefore: Bool, adapterDisabled: Bool = false) {
            self.adapterDisabled = adapterDisabled
            self.percent = percent
            self.external = external
            self.sleeping = sleeping
            self.limit = limit
            self.dischargeTo = dischargeTo
            self.leaseValid = leaseValid
            self.chargingBefore = chargingBefore
        }
    }

    public struct Output: Equatable, Sendable {
        public var adapterOn: Bool
        public var chargingAllowed: Bool
    }

    /// 停充后降到上限下面 3% 再恢复，免得反复开关。
    public static let rechargeBand = 3

    public static func decide(_ input: Input) -> Output {
        // 只有醒着、接着电源、指令没过期、电量高于目标和最低线时才断开电源。睡眠时一律接回，免得合盖放空。
        var adapterOn = true
        if let target = input.dischargeTo, let percent = input.percent, input.external || input.adapterDisabled, input.leaseValid, !input.sleeping,
           percent > max(target, ChargePolicy.dischargeFloor) {
            adapterOn = false
        }

        guard let limit = input.limit, limit < 100, let percent = input.percent else {
            return Output(adapterOn: adapterOn, chargingAllowed: true)
        }
        var charging: Bool
        if input.sleeping {
            // 睡着时没法在上限处停下来。电量离上限还远就先充，否则停着。
            charging = percent < limit - 10
        } else if percent >= limit {
            charging = false
        } else if percent <= limit - rechargeBand {
            charging = true
        } else {
            charging = input.chargingBefore
        }
        if !adapterOn { charging = false }
        return Output(adapterOn: adapterOn, chargingAllowed: charging)
    }
}

extension HelperRequest {
    public static func decode(_ data: Data) -> HelperRequest? { try? JSONDecoder().decode(HelperRequest.self, from: data) }
}

extension HelperStatus {
    public static func decode(_ data: Data) -> HelperStatus? { try? JSONDecoder().decode(HelperStatus.self, from: data) }
}

public enum HelperCoding {
    /// 一行 JSON，末尾带换行。
    public static func line<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }
}
