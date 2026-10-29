import AppKit
import Foundation
import BatteryCore

/// `--bench`：量一下几件每 30 秒都要做的事要多久，超过预算就以非零状态退出，CI 靠它守住性能。
enum Benchmark {
    struct Check {
        var name: String
        var value: Double
        var limit: Double
        var unit: String
        var ok: Bool { value <= limit }
    }

    @MainActor
    static func run() -> Bool {
        var checks: [Check] = []

        func measure(_ name: String, runs: Int, limit: Double, _ body: () -> Void) {
            body() // 预热
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<runs { body() }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6 / Double(runs)
            checks.append(Check(name: name, value: elapsed, limit: limit, unit: "ms/次"))
        }

        // 每 30 秒一次：读电池、内存、系统充电上限。pmset 有缓存，不算在内。
        measure("读系统（不含 pmset）", runs: 20, limit: 60) {
            _ = SystemReaders.read(lowPowerAge: 3600)
        }
        measure("读 pmset（起一个进程）", runs: 3, limit: 400) {
            _ = SystemReaders.lowPower()
        }

        let schedule = (try? Schedule.compile(Schedule.makeDefaults()).get()) ?? .empty
        measure("时间表编译", runs: 500, limit: 2) {
            _ = Schedule.compile(Schedule.makeDefaults())
        }
        measure("预测 8 小时", runs: 200, limit: 5) {
            _ = Forecast.points(schedule: schedule, minute: 6 * 60, percent: 95, external: true,
                                deadline: ClockTime(hour: 23, minute: 30), chargeRate: 0.33, dischargeAvailable: true, horizon: 480)
        }
        measure("画菜单栏图标", runs: 200, limit: 3) {
            _ = MenuBarIcon.image(top: "80%", bottom: "接通", level: 0.8, charging: true)
        }

        var history = ChargeHistory()
        let now = Date()
        for index in 0..<1100 {
            history.add(ChargeSample(t: now.addingTimeInterval(Double(index - 1100) * 240), p: 50 + index % 40, c: index % 3 == 0, x: true, l: 80))
        }
        measure("72 小时历史：取 16 小时 + 学速度", runs: 100, limit: 3) {
            _ = history.samples(since: now.addingTimeInterval(-16 * 3600))
            _ = history.learnedRate()
        }
        measure("历史写盘", runs: 10, limit: 30) {
            try? history.save(to: FileManager.default.temporaryDirectory.appendingPathComponent("mbc-bench-history.json"))
        }

        let footprint = Double(physFootprint()) / 1_048_576
        checks.append(Check(name: "内存占用（跑完以上之后）", value: footprint, limit: 120, unit: "MB"))

        var ok = true
        for check in checks {
            let mark = check.ok ? "ok  " : "超了"
            print(String(format: "%@ %-28@ %8.2f %@（预算 %.0f）", mark, check.name as NSString, check.value, check.unit as NSString, check.limit))
            if !check.ok { ok = false }
        }
        return ok
    }

    private static func physFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
