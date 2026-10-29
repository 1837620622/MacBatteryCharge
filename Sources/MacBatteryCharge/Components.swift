import SwiftUI
import BatteryCore

/// 一块圆角卡片。底色和描边都取系统的前景色淡化，深浅色模式自动跟着变。
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5))
    }
}

/// 「上排」「下排」这样的分段标题。
struct SectionTitle: View {
    var title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 读数一行：左边名称，右边数值。
struct ReadingRow: View {
    var name: String
    var value: String
    var symbol: String
    var tint: Color = .secondary
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(name)
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).monospacedDigit().multilineTextAlignment(.trailing)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
    }
}

/// 窗口顶部的提示条。
struct Banner<Actions: View>: View {
    var symbol: String
    var tint: Color
    var title: String
    var detail: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.callout.weight(.semibold))
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) { actions }
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
    }
}

/// 电量圆环。外圈一小段刻度标出当前上限。
struct BatteryRing: View {
    var percent: Int?
    var limit: Int
    var flow: PowerFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { Double(percent ?? 0) / 100 }

    private var tint: Color {
        guard let percent else { return .secondary }
        switch flow {
        case .charging: return .green
        case .discharging: return percent <= 20 ? .red : (percent <= 40 ? .orange : .accentColor)
        default: return .accentColor
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 10)
                .padding(5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(5)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: fraction)
            // 上限的位置
            Capsule()
                .fill(Color.primary)
                .frame(width: 3, height: 16)
                .offset(y: -45)
                .rotationEffect(.degrees(Double(limit) / 100 * 360))
                .opacity(percent == nil ? 0 : 0.85)
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(percent.map(String.init) ?? "—")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if percent != nil {
                        Text("%").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: flowSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: flow == .charging && !reduceMotion)
            }
        }
        .frame(width: 100, height: 100)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent.map { "电量 \($0)%，上限 \(limit)%" } ?? "没有电池")
    }

    private var flowSymbol: String {
        switch flow {
        case .charging: return "bolt.fill"
        case .discharging: return "arrow.down"
        case .plugged: return "powerplug.fill"
        case .battery: return "battery.75percent"
        case .noBattery: return "powerplug"
        }
    }
}

/// 一天 24 小时的时间表条。颜色越深上限越高，竖线是现在。
struct TimelineBar: View {
    var schedule: Schedule
    var minute: Int
    var selectedIndex: Int?
    var onSelect: (Int) -> Void

    static func opacity(for limit: Int) -> Double {
        switch limit {
        case ..<81: return 0.35
        case ..<86: return 0.48
        case ..<91: return 0.6
        case ..<96: return 0.74
        default: return 0.9
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    ForEach(Array(schedule.blocks.enumerated()), id: \.offset) { _, block in
                        let x = width * CGFloat(block.start) / 1440
                        let w = max(1, width * CGFloat(block.length) / 1440)
                        blockView(block, width: w)
                            .frame(width: w, height: 30)
                            .offset(x: x)
                            .onTapGesture { if let index = block.index { onSelect(index) } }
                    }
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 38)
                        .offset(x: width * CGFloat(minute) / 1440 - 1, y: -4)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                    if hour != 24 { Spacer(minLength: 0) }
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func blockView(_ block: Schedule.Block, width: CGFloat) -> some View {
        let selected = block.index != nil && block.index == selectedIndex
        ZStack {
            if block.index == nil {
                Rectangle().fill(Color.primary.opacity(0.06))
            } else {
                Rectangle().fill(Color.accentColor.opacity(Self.opacity(for: block.limit)))
            }
            if width > 34 {
                Text("\(block.limit)%")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(block.index == nil ? Color.secondary : Color.white)
            }
        }
        .overlay(Rectangle().strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 2))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color(nsColor: .windowBackgroundColor)).frame(width: 1)
        }
        .contentShape(Rectangle())
    }

    private var accessibilityText: String {
        let parts = schedule.blocks.map { block in
            "\(ClockTime(minuteOfDay: block.start).text) 起 \(block.limit)%" + (block.index == nil ? "（空档）" : "")
        }
        return "时间表：" + parts.joined(separator: "，")
    }
}
