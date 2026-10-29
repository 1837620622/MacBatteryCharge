import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import BatteryCore
import SMCBridge

// 以 root 运行的放电帮手。只做：断开或接回电源适配器、停止充电或写 Intel 的 BCLM 上限、报告状态。
// 不联网，不读文件，只听本机一个套接字，只认安装它的那个用户。
// 能写哪些键、写什么值只在这个文件里决定；软件只能说“要什么状态”，不能指定键名。

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

typealias KeyWrite = (key: String, off: [UInt8], on: [UInt8])

struct Controls {
    var adapterKeys: [KeyWrite] = []
    var chargeKind = HelperChargeControl.none
    var chargeKeys: [KeyWrite] = []
}

/// 是不是 Intel 机器。用运行时判断，Universal 或 Rosetta 下也不会走错分支。
var isIntelMac: Bool {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let ok = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    return !ok
}

/// 只探测一次。哪些键存在，决定这台机器用哪种方式。
func probe() -> Controls {
    var controls = Controls()
    guard SMCOpen() else { return controls }
    // 断开电源只用一个键，和 Calma 一样：新固件用 CHIE，老的用 CH0I。同时写两个，一个失败时状态就对不上了。
    if SMCHasKey("CHIE") {
        controls.adapterKeys = [("CHIE", [8], [0])]
    } else if SMCHasKey("CH0I") {
        controls.adapterKeys = [("CH0I", [1], [0])]
    }
    // BCLM 是 Intel 机器硬件里的充电上限（百分比）。按运行时判断，不看编译时的架构：
    // 同一次构建在 Rosetta 下跑起来也是 x86_64，会去写只有 Intel 才有的键。
    if isIntelMac, SMCHasKey("BCLM") {
        controls.chargeKind = .intelCeiling
        return controls
    }
    // 有 bf* 的机器上限通常由系统管，但不等于没有别的路可走：
    // 所以先记下 .system，接着往下探，探到 CH0B/CH0C 或 CHTE 就用它们，真的没有才回到 .system。
    let hasSystemKeys = SMCHasKey("bfF0") && SMCHasKey("bfD0") && SMCHasKey("bfE0")
    if SMCHasKey("CH0B") && SMCHasKey("CH0C") {
        controls.chargeKind = .direct
        controls.chargeKeys = [("CH0B", [2], [0]), ("CH0C", [2], [0])]
    } else if SMCHasKey("CHTE") {
        controls.chargeKind = .direct
        controls.chargeKeys = [("CHTE", [1, 0, 0, 0], [0, 0, 0, 0])]
    } else if hasSystemKeys {
        // 帮手不碰 bf* 键：它们的含义还没有公开资料确认。这一台的充电上限只能靠系统自己管。
        controls.chargeKind = .system
    }
    return controls
}

let controls = probe()

/// 写一组键。全部成功才算成功。
func writeKeys(_ keys: [KeyWrite], on: Bool) -> Bool {
    var ok = true
    for item in keys {
        let bytes = on ? item.on : item.off
        if !SMCWriteBytes(item.key, bytes, bytes.count) { ok = false }
    }
    return ok
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
var resumeAt: Int?
var leaseUntil = Date.distantPast
var lastApply = Date()
var sleeping = false
var chargingAllowed = true
var adapterOn = true
var ceiling: UInt8?
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
        say(lastError ?? "")
    }
}

/// Intel：把 BCLM 写成上限。硬件自己会停。只在数值变化时写。
func setCeiling(_ percent: Int) {
    guard controls.chargeKind == .intelCeiling else { return }
    let value = UInt8(min(100, max(20, percent)))
    if ceiling == value { return }
    if SMCWriteBytes("BCLM", [value], 1) {
        ceiling = value
        lastError = nil
        say("BCLM 上限写成 \(value)%")
    } else {
        lastError = "写 BCLM 失败"
        say(lastError ?? "")
    }
}

func evaluate() {
    let battery = readBattery()
    // 上限 24 小时没有人续期（程序不再开），就放掉，免得电池一直被限在低处。
    if limit != nil, Date().timeIntervalSince(lastApply) > HelperInfo.limitLifetime {
        limit = nil
        say("上限 24 小时没有续期，恢复原样")
    }
    let input = HelperPolicy.Input(
        percent: battery.percent, external: battery.external, sleeping: sleeping,
        limit: controls.chargeKind == .direct ? limit : nil,
        dischargeTo: controls.adapterKeys.isEmpty ? nil : dischargeTo,
        resumeAt: resumeAt,
        leaseValid: Date() < leaseUntil, chargingBefore: chargingAllowed, adapterDisabled: !adapterOn)
    let output = HelperPolicy.decide(input)
    setAdapter(output.adapterOn)
    setCharging(output.chargingAllowed)
    setCeiling(limit ?? 100)
    if Date() >= leaseUntil, dischargeTo != nil {
        dischargeTo = nil
        resumeAt = nil
    }
}

func resetAll() {
    limit = nil
    dischargeTo = nil
    resumeAt = nil
    leaseUntil = .distantPast
    setAdapter(true)
    setCharging(true)
    setCeiling(100)
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
        lastApply = Date()
        limit = request.limit.map { min(100, max(50, $0)) }
        if let target = request.dischargeTo {
            let clampedTarget = min(100, max(ChargePolicy.dischargeFloor, target))
            dischargeTo = clampedTarget
            resumeAt = request.resumeAt.map { min(clampedTarget, max(ChargePolicy.dischargeFloor, $0)) }
            leaseUntil = Date().addingTimeInterval(Double(min(HelperInfo.maxLease, max(10, request.lease ?? 120))))
        } else {
            dischargeTo = nil
            resumeAt = nil
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
            // 客户端 3 秒超时后会先 close，那时候这里的 write 会吃到 SIGPIPE，默认动作是杀掉进程。
            // 帮手是被 launchd 看活的，被杀会中断放电、并把电源接回去，所以这一行是必需的。
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
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
            // 短写要接着写，不能只调用一次就丢掉剩下的。
            response.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                var sent = 0
                while sent < buffer.count {
                    let written = write(client, base + sent, buffer.count - sent)
                    if written <= 0 { break }
                    sent += written
                }
            }
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

say("启动，版本 \(appVersion)，断电 \(controls.adapterKeys.map(\.key)) 充电 \(controls.chargeKind.rawValue)")
// 上次异常退出时 SMC 里可能还留着断开或停充的状态，启动先强制恢复。
adapterOn = false
chargingAllowed = false
queue.sync { resetAll() }
serve()
watchSleep()

let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(2))
timer.setEventHandler { evaluate() }
timer.resume()

var signalSources: [DispatchSourceSignal] = []
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
