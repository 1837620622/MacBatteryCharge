import Foundation
import IOKit
import IOKit.ps
import BatteryCore
import PowerBridge

/// 跑一个命令，等它结束。只在后台队列用。
enum Shell {
    struct Output {
        var status: Int32
        var out: String
        var err: String
    }

    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return Output(status: -1, out: "", err: error.localizedDescription)
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(status: process.terminationStatus,
                      out: String(decoding: outData, as: UTF8.self),
                      err: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 给 AppleScript 的 do shell script 用：整段放进单引号。
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 用系统的管理员密码框跑一段 shell。取消时返回 cancelled。
    enum AdminResult: Equatable {
        case ok
        case cancelled
        case failed(String)
    }

    static func runAsAdmin(_ script: String, prompt: String) -> AdminResult {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let apple = "do shell script \"\(escape(script))\" with prompt \"\(escape(prompt))\" with administrator privileges"
        let result = run("/usr/bin/osascript", ["-e", apple])
        if result.status == 0 { return .ok }
        if result.err.contains("-128") { return .cancelled }
        return .failed(result.err.isEmpty ? "系统没有执行" : result.err)
    }
}

enum ChargeLimitState: Equatable, Sendable {
    case unknown
    case unsupported(String)
    case current(Int)

    var value: Int? {
        if case .current(let value) = self { return value }
        return nil
    }

    var isSupported: Bool {
        if case .current = self { return true }
        return false
    }
}

/// 充电上限都走同一条串行队列，避免并发调用 PowerUI。
enum ChargeBridge {
    static let queue = DispatchQueue(label: "com.macbatterycharge.charge", qos: .userInitiated)

    static func read() -> ChargeLimitState {
        queue.sync {
            var error: NSString?
            guard MBCChargeSupported(&error) else { return .unsupported(error as String? ?? "这台 Mac 不支持系统充电上限") }
            var limit = 0
            guard MBCChargeGetLimit(&limit, &error) else { return .unsupported(error as String? ?? "读不到充电上限") }
            return .current(limit)
        }
    }

    static func write(_ limit: Int) -> String? {
        queue.sync {
            var error: NSString?
            guard MBCChargeSupported(&error) else { return error as String? ?? "这台 Mac 不支持系统充电上限" }
            if MBCChargeSetLimit(limit, &error) { return nil }
            return error as String? ?? "设置充电上限失败"
        }
    }
}

struct SystemReading: Sendable {
    var battery: BatterySnapshot
    var memory: MemorySnapshot
    var chargeLimit: ChargeLimitState
    var lowPower: LowPowerState?
    var thermal: ProcessInfo.ThermalState
    var date: Date
    var helper: HelperStatus? = nil
}

enum SystemReaders {
    /// lowPowerAge：pmset 要起一个进程，窗口没开时 10 分钟读一次就够。
    static func read(lowPowerAge: TimeInterval = 0) -> SystemReading {
        let helper = FileManager.default.fileExists(atPath: HelperInfo.socketPath) ? HelperClient.status() : nil
        return SystemReading(battery: battery(), memory: memory(), chargeLimit: ChargeBridge.read(),
                             lowPower: lowPower(maxAge: lowPowerAge), thermal: ProcessInfo.processInfo.thermalState,
                             date: Date(), helper: helper)
    }

    static func battery() -> BatterySnapshot {
        BatterySnapshot(registry: registry(), powerSource: internalPowerSource(), adapter: adapterDetails())
    }

    static func registry() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return dictionary
    }

    static func internalPowerSource() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType { return description }
        }
        return nil
    }

    static func adapterDetails() -> [String: Any]? {
        IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
    }

    static func memory() -> MemorySnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pressure: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0) != 0 { pressure = 0 }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            var memory = MemorySnapshot()
            memory.totalBytes = total
            memory.pressure = Int(pressure)
            return memory
        }
        return MemorySnapshot(totalBytes: total, pageSize: UInt64(getpagesize()),
                              free: UInt64(stats.free_count), active: UInt64(stats.active_count),
                              inactive: UInt64(stats.inactive_count), wired: UInt64(stats.wire_count),
                              compressed: UInt64(stats.compressor_page_count), speculative: UInt64(stats.speculative_count),
                              pressure: Int(pressure))
    }

    private static let lowPowerLock = NSLock()
    nonisolated(unsafe) private static var lowPowerCache: (value: LowPowerState?, at: Date)?

    static func lowPower(maxAge: TimeInterval = 0) -> LowPowerState? {
        lowPowerLock.lock()
        defer { lowPowerLock.unlock() }
        if maxAge > 0, let cache = lowPowerCache, Date().timeIntervalSince(cache.at) < maxAge { return cache.value }
        let result = Shell.run("/usr/bin/pmset", ["-g", "custom"])
        let value = result.status == 0 ? LowPowerState.parse(custom: result.out) : nil
        lowPowerCache = (value, Date())
        return value
    }

    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }
}

enum LowPowerWriter {
    enum Outcome: Equatable {
        case done
        case cancelled
        case failed(String)
    }

    /// 只在点「立即应用」时调用。系统会弹出自己的管理员密码框，密码不经过本软件。
    static func apply(_ choice: LowPowerChoice, key: String, hasBattery: Bool) -> Outcome {
        let modes = choice.modes
        var commands: [String] = []
        if hasBattery { commands.append("/usr/bin/pmset -b \(key) \(modes.battery)") }
        commands.append("/usr/bin/pmset -c \(key) \(modes.ac)")
        switch Shell.runAsAdmin(commands.joined(separator: "; "), prompt: "充电上限要按这一段的设置修改低电量模式。") {
        case .ok: return .done
        case .cancelled: return .cancelled
        case .failed(let text): return .failed(text)
        }
    }
}
