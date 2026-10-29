import SwiftUI
import BatteryCore

// MARK: 提示条

/// 窗口顶部的提示条。一行标题，最多再一行说明。
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
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) { actions }
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
    }
}

// MARK: 小件

/// 一个读数：名称、数值、可选的一行小字。
struct Tile: View {
    var symbol: String
    var title: String
    var value: String
    var note: String?
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: value)
            Text(note ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 长一点的说明收进这个小圆点里，点一下才看。
struct InfoButton: View {
    var text: String
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel("说明")
        .accessibilityHint(text)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .padding(12)
                .frame(width: 240, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 一行：名称，可选的说明圆点，右边开关。
struct ToggleRow: View {
    var title: String
    var info: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let info { InfoButton(text: info) }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// 每读到一次新数据，亮一下。
struct LiveDot: View {
    var stamp: Date?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1.7 : 1)
                .opacity(pulse ? 0.45 : 1)
            Text("实时").font(.caption2).foregroundStyle(.secondary)
        }
        .onChange(of: stamp) { _ in
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeOut(duration: 0.6)) { pulse = false }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("数据实时更新")
    }
}

// MARK: 动态画面

/// 液体电量盘：水面随电量升降，波浪一直在动；虚线是现在的上限。
/// level 可以被动画推着走，所以电量变化时水面是滑上去的。
struct LiquidDisc: View, Animatable {
    var level: Double
    var limit: Int
    var tint: Color
    var flow: PowerFlow
    var live: Bool

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !live)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                draw(&gc, size: size, time: time)
            }
        }
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize, time: Double) {
        let w = size.width
        let h = size.height
        let surface = h * (1 - min(max(level, 0), 1))

        if level > 0 {
            let amplitude: Double = flow == .charging ? 3.4 : (flow == .discharging ? 2.6 : 1.8)
            let speed: Double = flow == .charging ? 1.5 : 0.8
            for layer in 0..<2 {
                var path = Path()
                let phase = time * speed * (layer == 0 ? 1 : -1.3) + Double(layer) * 1.7
                path.move(to: CGPoint(x: 0, y: h))
                var x = 0.0
                while x <= w {
                    let y = surface + amplitude * sin(x / w * 2 * .pi * 1.6 + phase)
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += 3
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
                gc.fill(path, with: .color(tint.opacity(layer == 0 ? 0.62 : 0.32)))
            }
            if flow == .charging && h - surface > 14 {
                let travel = h - surface - 6
                for index in 0..<5 {
                    let seed = Double(index)
                    let rise = (time * (11 + seed * 2.5) + seed * 19).truncatingRemainder(dividingBy: travel)
                    let x = w * (0.22 + 0.14 * seed) + 3 * sin(time * 1.4 + seed)
                    let radius = 1.4 + 0.5 * Double(index % 3)
                    let rect = CGRect(x: x - radius, y: h - rise - radius, width: radius * 2, height: radius * 2)
                    gc.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.5)))
                }
            }
        }

        let limitY = h * (1 - Double(limit) / 100)
        var line = Path()
        line.move(to: CGPoint(x: 0, y: limitY))
        line.addLine(to: CGPoint(x: w, y: limitY))
        gc.stroke(line, with: .color(.primary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }
}

/// 电量圆盘：液体盘、外圈、中间的大数字。
struct LiquidRing: View {
    var percent: Int?
    var limit: Int
    var flow: PowerFlow
    var live: Bool

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
            Circle().fill(Color.primary.opacity(0.06))
            LiquidDisc(level: Double(percent ?? 0) / 100, limit: limit, tint: tint, flow: flow, live: live)
                .clipShape(Circle())
                .animation(.easeInOut(duration: 0.9), value: percent)
            Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(percent.map(String.init) ?? "—")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.3), value: percent)
                if percent != nil {
                    Text("%").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .shadow(color: Color(nsColor: .windowBackgroundColor).opacity(0.7), radius: 3)
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent.map { "电量 \($0)%，上限 \(limit)%" } ?? "没有电池")
    }
}

/// 一条会流动的线：圆点沿着线走，方向就是电流的方向。
struct FlowLane: View {
    var active: Bool
    /// 1 向右，-1 向左。
    var direction: Double
    var tint: Color
    var live: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(live && active))) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                let color: Color = active ? tint : .primary.opacity(0.18)
                let phase = active ? -direction * time * 22 : 0
                gc.stroke(line, with: .color(color),
                          style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 7], dashPhase: phase))
            }
        }
        .frame(height: 18)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// 电源 → 电脑 ⇄ 电池。有电流的那段圆点在走。
struct FlowStrip: View {
    var plugged: Bool
    var adapterCut: Bool
    var adapterWatts: Int?
    var batteryWatts: Double?
    var live: Bool

    private var watts: Double { batteryWatts ?? 0 }
    private var charging: Bool { watts >= 0.3 }
    private var draining: Bool { watts <= -0.3 }

    var body: some View {
        HStack(spacing: 6) {
            node(symbol: "powerplug.fill", caption: adapterText, tint: plugged && !adapterCut ? .accentColor : .secondary)
            FlowLane(active: plugged && !adapterCut, direction: 1, tint: .accentColor, live: live)
            node(symbol: "laptopcomputer", caption: nil, tint: .primary)
            FlowLane(active: charging || draining, direction: charging ? 1 : -1, tint: charging ? .green : .orange, live: live)
            node(symbol: batterySymbol, caption: batteryText, tint: charging ? .green : (draining ? .orange : .secondary))
        }
        .frame(height: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func node(symbol: String, caption: String?, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(tint)
            Text(caption ?? " ")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.25), value: caption)
        }
        .frame(width: 54)
    }

    private var adapterText: String? {
        if adapterCut { return "已断开" }
        guard plugged else { return "未接" }
        return adapterWatts.map { "\($0) W" } ?? "已接"
    }

    private var batteryText: String {
        if charging { return String(format: "+%.1f W", watts) }
        if draining { return String(format: "−%.1f W", abs(watts)) }
        return "0 W"
    }

    private var batterySymbol: String {
        if charging { return "battery.100.bolt" }
        if draining { return "battery.50" }
        return "battery.100"
    }

    private var accessibilityText: String {
        var parts: [String] = []
        parts.append(adapterCut ? "电源适配器已断开" : (plugged ? "接着电源" : "没接电源"))
        parts.append(charging ? "电池正在充入" : (draining ? "电池正在放出" : "电池不进不出"))
        return parts.joined(separator: "，")
    }
}

// MARK: 时间表条

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
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 3, height: 38)
                        .offset(x: width * CGFloat(minute) / 1440 - 1.5, y: -4)
                        .animation(.easeInOut(duration: 0.6), value: minute)
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
