import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import BatteryCore
import SMCBridge

// 以 root 运行的放电帮手。只做：断开/接回电源适配器、旧系统上停充/恢复、报告状态。
// 不联网，不读文件，只听本机一个套接字，并且只认安装它的那个用户。

setvbuf(stdout, nil, _IOLBF, 0)

func say(_ text: String) { print("[helper] \(text)") }

let arguments = CommandLine.arguments
func argument(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
let appVersion = argument("--app-version") ?? "0"
guard let allowedUID = argument("--uid").flatMap({ uid_t($0) }) else {
    say("缺少 --uid，退出")
    exit(64)
}

// MARK: SMC

struct Controls {
    var adapterKeys: [(key: String, off: [UInt8], on: [UInt8])] = []
    var chargeKind = HelperChargeControl.none
    var chargeKeys: [(key: String, off: [UInt8], on: [UInt8])] = []
    var systemLimit = false
}

func probe() -> Controls {
    var controls = Controls()
    guard SMCOpen() else { return controls }
    if SMCHasKey("CH0I") && SMCHasKey("CH0J") {
        controls.adapterKeys = [("CH0I", [1], [0]), ("CH0J", [1], [0])]
    } else if SMCHasKey("CH0I") {
        controls.adapterKeys = [("CH0I", [1], [0])]
    } else if SMCHasKey("CH0J") {
        controls.adapterKeys = [("CH0J", [1], [0])]
    } else if SMCHasKey("CHIE") {
        controls.adapterKeys = [("CHIE", [8], [0])]
    }
    // 固件自带上限（bfF0/bfD0/bfE0）的 Mac 由系统的充电上限管，帮手不碰充电。
    if SMCHasKey("bfF0") && SMCHasKey("bfD0") && SMCHasKey("bfE0") {
        controls.chargeKind = .system
        controls.systemLimit = true
    } else if SMCHasKey("CH0B") && SMCHasKey("CH0C") {
        controls.chargeKind = .direct
        controls.chargeKeys = [("CH0B", [2], [0]), ("CH0C", [2], [0])]
    } else if SMCHasKey("CHTE") {
        controls.chargeKind = .direct
        controls.chargeKeys = [("CHTE", [1, 0, 0, 0], [0, 0, 0, 0])]
    }
    return controls
}

let controls = probe()

func writeKeys(_ keys: [(key: String, off: [UInt8], on: [UInt8])], on: Bool) -> Bool {
    var ok = true
    for item in keys {
        let bytes = on ? item.on : item.off
        if !SMCWriteBytes(item.key, bytes, bytes.count) { ok = false }
    }
    return ok
}

func readFlag(_ keys: [(key: String, off: [UInt8], on: [UInt8])]) -> Bool? {
    guard let first = keys.first else { return nil }
    var buffer = [UInt8](repeating: 0, count: 32)
    let count = SMCReadBytes(first.key, &buffer, buffer.count)
    guard count > 0 else { return nil }
    return Array(buffer[0..<Int(count)]) == first.on
}

// MARK: 电量

func readBattery() -> (percent: Int?, external: Bool) {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, false) }
    for source in list {
        guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
        let percent = description[kIOPSCurrentCapacityKey] as? Int
        let external = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        return (percent, external)
    }
    return (nil, false)
}

// MARK: 状态（都在 queue 上改）

let queue = DispatchQueue(label: "com.macbatterycharge.helper.state")
var limit: Int?
var dischargeTo: Int?
var leaseUntil = Date.distantPast
var sleeping = false
var chargingAllowed = true
var adapterOn = true
var lastError: String?

func setAdapter(_ on: Bool) {
    guard !controls.adapterKeys.isEmpty else { return }
    if adapterOn == on { return }
    if writeKeys(controls.adapterKeys, on: on) {
        adapterOn = on
        lastError = nil
        say(on ? "电源适配器接回" : "断开电源适配器，用电池放电")
    } else {
        lastError = "写 SMC 失败：\(controls.adapterKeys.map(\.key).joined(separator: "/"))"
        say(lastError ?? "")
    }
}

func setCharging(_ allowed: Bool) {
    guard controls.chargeKind == .direct else { return }
    if chargingAllowed == allowed { return }
    if writeKeys(controls.chargeKeys, on: allowed) {
        chargingAllowed = allowed
        say(allowed ? "允许充电" : "停止充电")
    } else {
        lastError = "写 SMC 失败：\(controls.chargeKeys.map(\.key).joined(separator: "/"))"
    }
}

func evaluate() {
    let battery = readBattery()
    let input = HelperPolicy.Input(
        percent: battery.percent, external: battery.external, sleeping: sleeping,
        limit: controls.chargeKind == .direct ? limit : nil,
        dischargeTo: controls.adapterKeys.isEmpty ? nil : dischargeTo,
        leaseValid: Date() < leaseUntil, chargingBefore: chargingAllowed, adapterDisabled: !adapterOn)
    let output = HelperPolicy.decide(input)
    setAdapter(output.adapterOn)
    setCharging(output.chargingAllowed)
    if Date() >= leaseUntil, dischargeTo != nil { dischargeTo = nil }
}

func resetAll() {
    limit = nil
    dischargeTo = nil
    leaseUntil = .distantPast
    setAdapter(true)
    setCharging(true)
}

func status() -> HelperStatus {
    let battery = readBattery()
    let remaining = max(0, Int(leaseUntil.timeIntervalSinceNow.rounded(.up)))
    return HelperStatus(
        version: appVersion,
        adapterControl: !controls.adapterKeys.isEmpty,
        chargeControl: controls.chargeKind,
        adapterEnabled: controls.adapterKeys.isEmpty ? nil : adapterOn,
        chargingEnabled: controls.chargeKind == .direct ? chargingAllowed : nil,
        percent: battery.percent, external: battery.external,
        limit: limit, dischargeTo: dischargeTo, leaseRemaining: remaining,
        sleeping: sleeping, error: lastError)
}

func handle(_ request: HelperRequest) -> HelperStatus {
    switch request.cmd {
    case .status:
        break
    case .reset:
        resetAll()
    case .apply:
        limit = request.limit.map { min(100, max(50, $0)) }
        if let target = request.dischargeTo {
            dischargeTo = min(100, max(ChargePolicy.dischargeFloor, target))
            leaseUntil = Date().addingTimeInterval(Double(min(HelperInfo.maxLease, max(10, request.lease ?? 120))))
        } else {
            dischargeTo = nil
            leaseUntil = .distantPast
        }
        evaluate()
    }
    return status()
}

// MARK: 套接字

func serve() {
    unlink(HelperInfo.socketPath)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { say("socket 失败"); exit(70) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let path = HelperInfo.socketPath
    let pathSize = MemoryLayout.size(ofValue: address.sun_path)
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: pathSize) { chars in
            _ = path.withCString { strncpy(chars, $0, pathSize - 1) }
        }
    }
    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0 else { say("bind 失败：\(errno)"); exit(70) }
    chmod(path, 0o600)
    chown(path, allowedUID, 0)
    listen(fd, 8)

    DispatchQueue(label: "com.macbatterycharge.helper.accept").async {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { continue }
            var timeout = timeval(tv_sec: 3, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == allowedUID || uid == 0 else {
                close(client)
                continue
            }
            var data = Data()
            var byte: UInt8 = 0
            while data.count < 4096, read(client, &byte, 1) == 1, byte != 0x0A { data.append(byte) }
            var response: Data
            if let request = HelperRequest.decode(data) {
                response = HelperCoding.line(queue.sync { handle(request) })
            } else {
                response = HelperCoding.line(HelperStatus(version: appVersion, adapterControl: false, chargeControl: .none, error: "看不懂的请求"))
            }
            response.withUnsafeBytes { _ = write(client, $0.baseAddress, $0.count) }
            close(client)
        }
    }
}

// MARK: 睡眠

var rootPort: io_connect_t = 0
var notifyPort: IONotificationPortRef?
var notifier: io_object_t = 0

let kCanSystemSleep: UInt32 = 0xe000_0270
let kSystemWillSleep: UInt32 = 0xe000_0280
let kSystemHasPoweredOn: UInt32 = 0xe000_0300

func watchSleep() {
    let callback: IOServiceInterestCallback = { _, _, message, argument in
        switch message {
        case kCanSystemSleep:
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case kSystemWillSleep:
            queue.sync {
                sleeping = true
                evaluate()
            }
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case kSystemHasPoweredOn:
            queue.async {
                sleeping = false
                evaluate()
            }
        default:
            break
        }
    }
    rootPort = IORegisterForSystemPower(nil, &notifyPort, callback, &notifier)
    guard rootPort != 0, let port = notifyPort else { say("睡眠通知注册失败"); return }
    IONotificationPortSetDispatchQueue(port, DispatchQueue(label: "com.macbatterycharge.helper.power"))
}

// MARK: 启动

say("启动，版本 \(appVersion)，适配器控制 \(!controls.adapterKeys.isEmpty)，充电控制 \(controls.chargeKind.rawValue)")
// 上次异常退出时 SMC 里可能还留着断开的状态，启动先强制接回。
adapterOn = false
chargingAllowed = false
queue.sync { resetAll() }
serve()
watchSleep()

var signalSources: [DispatchSourceSignal] = []
let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(2))
timer.setEventHandler { evaluate() }
timer.resume()

for signalNumber in [SIGTERM, SIGINT] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
    source.setEventHandler {
        resetAll()
        unlink(HelperInfo.socketPath)
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

dispatchMain()
