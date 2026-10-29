import Foundation

public struct MemorySnapshot: Equatable, Sendable {
    public var totalBytes: UInt64 = 0
    public var usedBytes: UInt64 = 0
    public var availableBytes: UInt64 = 0
    /// kern.memorystatus_vm_pressure_level：1 正常，2 偏紧，4 紧张，8 严重，0 没读到。
    public var pressure = 0

    public init() {}

    /// 已用按活跃、联动和压缩估算；可用按空闲、不活跃和预读估算。都是页数。
    public init(totalBytes: UInt64, pageSize: UInt64, free: UInt64, active: UInt64, inactive: UInt64,
                wired: UInt64, compressed: UInt64, speculative: UInt64, pressure: Int) {
        let page = pageSize == 0 ? 4096 : pageSize
        var used = (active + wired + compressed) * page
        if totalBytes > 0 && used > totalBytes { used = totalBytes }
        self.totalBytes = totalBytes
        self.usedBytes = used
        self.availableBytes = (free + inactive + speculative) * page
        self.pressure = pressure
    }

    public var pressureText: String {
        switch pressure {
        case 1: return T("正常")
        case 2: return T("偏紧")
        case 4: return T("紧张")
        case 8: return T("严重")
        default: return T("未知")
        }
    }

    public var usedFraction: Double {
        totalBytes > 0 ? min(1, Double(usedBytes) / Double(totalBytes)) : 0
    }

    public static func bytesText(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    /// 读数一行：「6.2 / 16.0 GB · 正常」。
    public var summary: String {
        guard totalBytes > 0 else { return T("没有读到") }
        return "\(Self.bytesText(usedBytes)) / \(Self.bytesText(totalBytes)) · \(pressureText)"
    }
}
