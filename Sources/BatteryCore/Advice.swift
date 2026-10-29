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

/// 短句只从读数里来，不猜。每句尽量不超过一行。
public enum Advice {
    public static func items(battery: BatterySnapshot, memory: MemorySnapshot, limit: Int?, heatActive: Bool,
                             discharging: Bool = false) -> [AdviceItem] {
        guard battery.present else {
            return [AdviceItem(.info, "powerplug", T("没有内置电池。"))]
        }
        var items: [AdviceItem] = []
        let flow = battery.flow

        if heatActive {
            items.append(AdviceItem(.warn, "thermometer.high", T("电池偏热，先停在 80%。")))
        }

        if let percent = battery.percent, let limit {
            if discharging {
                items.append(AdviceItem(.info, "arrow.down.circle", T("放电中，放到 %@% 停。", ["\(limit)"])))
            } else if battery.externalConnected && percent > limit + 2 {
                items.append(AdviceItem(.info, "arrow.down.right", T("高于上限 %@%，只停充，不放电。", ["\(limit)"])))
            } else if flow == .plugged && percent >= limit - 1 {
                items.append(AdviceItem(.good, "checkmark.circle", T("停在上限，电源直接供电。")))
            }
        }

        if let watts = battery.adapterWatts, battery.externalConnected {
            if flow == .discharging && !discharging {
                items.append(AdviceItem(.warn, "bolt.trianglebadge.exclamationmark", T("充电器 %@ W 跟不上耗电。", ["\(watts)"])))
            } else if watts < 30 && flow == .charging {
                items.append(AdviceItem(.info, "tortoise", T("充电器 %@ W，充得慢。", ["\(watts)"])))
            }
        }

        if let celsius = battery.celsius {
            let text = String(format: "%.1f°C", celsius)
            if celsius >= 40 {
                items.append(AdviceItem(.warn, "thermometer.high", T("电池 %@，偏高。", ["\(text)"])))
            } else if celsius >= 10 {
                items.append(AdviceItem(.good, "thermometer.medium", T("电池 %@，正常。", ["\(text)"])))
            } else {
                items.append(AdviceItem(.info, "thermometer.low", T("电池 %@，偏冷，充得慢。", ["\(text)"])))
            }
        }
        if battery.thermallyLimited {
            items.append(AdviceItem(.info, "thermometer.sun", T("曾因过热放慢充电。")))
        }

        if let health = battery.health {
            if health < 80 {
                items.append(AdviceItem(.warn, "heart", T("健康约 %@%，可考虑换电池。", ["\(health)"])))
            } else {
                items.append(AdviceItem(.good, "heart", T("健康约 %@%（估算）。", ["\(health)"])))
            }
        }
        if let cycles = battery.cycles, let design = battery.designCycles, design > 0, cycles * 10 >= design * 8 {
            items.append(AdviceItem(.warn, "arrow.triangle.2.circlepath", T("循环 %@ / %@ 次，已用掉大半。", ["\(cycles)", "\(design)"])))
        }

        if memory.pressure >= 4 && flow == .discharging {
            items.append(AdviceItem(.warn, "memorychip", T("放电中，内存也紧。关掉不用的软件。")))
        } else if memory.pressure >= 4 {
            items.append(AdviceItem(.info, "memorychip", T("内存压力高。")))
        }
        return items
    }

    /// 窗口里最多放几条：先警告，再提示，最后正常。同一类保持原来的顺序。
    public static func top(_ items: [AdviceItem], count: Int = 3) -> [AdviceItem] {
        func rank(_ tone: AdviceItem.Tone) -> Int {
            switch tone {
            case .warn: return 0
            case .info: return 1
            case .good: return 2
            }
        }
        let sorted = items.enumerated().sorted { lhs, rhs in
            let l = rank(lhs.element.tone)
            let r = rank(rhs.element.tone)
            return l != r ? l < r : lhs.offset < rhs.offset
        }
        return sorted.prefix(count).map(\.element)
    }
}
