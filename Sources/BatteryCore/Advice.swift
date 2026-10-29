import Foundation

public struct AdviceItem: Identifiable, Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        case good
        case info
        case warn
    }

    public var tone: Tone
    /// SF Symbols 名称。
    public var symbol: String
    public var text: String
    public var id: String { text }

    public init(_ tone: Tone, _ symbol: String, _ text: String) {
        self.tone = tone
        self.symbol = symbol
        self.text = text
    }
}

/// 短句只从读数里来，不猜。
public enum Advice {
    public static func items(battery: BatterySnapshot, memory: MemorySnapshot, limit: Int?, heatActive: Bool) -> [AdviceItem] {
        guard battery.present else {
            return [AdviceItem(.info, "powerplug", "没有读到内置电池。台式机通常没有电池，充电上限也不会出现。")]
        }
        var items: [AdviceItem] = []
        let flow = battery.flow

        if heatActive {
            items.append(AdviceItem(.warn, "thermometer.high", "电池偏热，先停在 80%。降到 37°C 以下再按时间表继续。"))
        }

        if let percent = battery.percent, let limit {
            if battery.externalConnected && percent > limit + 2 {
                items.append(AdviceItem(.info, "arrow.down.right", "现在 \(percent)%，高于上限 \(limit)%。电量停在这里慢慢自然回落，不会为了降到 \(limit)% 去放电。"))
            } else if flow == .plugged && percent >= limit - 1 {
                items.append(AdviceItem(.good, "checkmark.circle", "已停在上限，电源直接供电，电池不再往上充。"))
            }
        }

        if let watts = battery.adapterWatts, battery.externalConnected {
            if flow == .discharging {
                items.append(AdviceItem(.warn, "bolt.trianglebadge.exclamationmark", "充电器 \(watts) W 跟不上耗电，电量还在往下走。换功率大一点的充电器，或者关掉暂时不用的软件。"))
            } else if watts < 30 && flow == .charging {
                items.append(AdviceItem(.info, "tortoise", "充电器 \(watts) W，充得会慢一些。"))
            }
        }

        if let celsius = battery.celsius {
            let text = String(format: "%.1f°C", celsius)
            if celsius >= 40 {
                items.append(AdviceItem(.warn, "thermometer.high", "电池 \(text) 偏高。放在硬平面上，不要盖住出风口。"))
            } else if celsius >= 10 {
                items.append(AdviceItem(.good, "thermometer.medium", "电池 \(text)，在常见范围内。"))
            } else {
                items.append(AdviceItem(.info, "thermometer.low", "电池 \(text) 偏冷，充电会变慢。"))
            }
        }
        if battery.thermallyLimited {
            items.append(AdviceItem(.info, "thermometer.sun", "系统记录过因过热而放慢充电。"))
        }

        if let health = battery.health {
            if health < 80 {
                items.append(AdviceItem(.warn, "heart", "满充容量约为设计容量的 \(health)%。白天停在 80% 能放慢损耗；低于 80% 可以考虑换电池。"))
            } else {
                items.append(AdviceItem(.good, "heart", "健康度约 \(health)%，按标称容量相对出厂设计容量估算。"))
            }
        }
        if let cycles = battery.cycles, let design = battery.designCycles, design > 0, cycles * 10 >= design * 8 {
            items.append(AdviceItem(.warn, "arrow.triangle.2.circlepath", "循环 \(cycles) 次，设计大约 \(design) 次，已经用掉大部分。"))
        }

        if memory.pressure >= 4 && flow == .discharging {
            items.append(AdviceItem(.warn, "memorychip", "正在放电，内存压力也高。关掉暂时不用的软件，耗电会少一些。"))
        } else if memory.pressure >= 4 {
            items.append(AdviceItem(.info, "memorychip", "内存压力高。这只说明内存，不说明电池坏了。"))
        }
        return items
    }
}
