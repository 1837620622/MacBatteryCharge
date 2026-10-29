import SwiftUI
import BatteryCore

/// 一天的圆盘，是窗口的主角。外圈是时间表：每一段一道弧，颜色深浅就是上限高低，空档是淡灰。
/// 圆盘里面是水，水面就是现在的电量，虚线是上限。圆点是现在的时间。点外圈的某一段，就打开它的设置。
struct DayDial: View {
    var schedule: Schedule
    var minute: Int
    var percent: Int?
    var limit: Int
    var flow: PowerFlow
    var live: Bool
    var selectedIndex: Int?
    var onSelect: (Int) -> Void

    private let diameter: CGFloat = 180
    private let ringWidth: CGFloat = 14

    private var innerDiameter: CGFloat { diameter - 2 * (ringWidth + 6) }

    var body: some View {
        ZStack {
            Canvas { context, size in
                drawRing(&context, size: size)
            }
            LiquidDisc(level: Double(percent ?? 0) / 100, limit: limit, tint: tint, flow: flow, live: live)
                .frame(width: innerDiameter, height: innerDiameter)
                .clipShape(Circle())
                .animation(.easeInOut(duration: 0.9), value: percent)
            VStack(spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(percent.map(String.init) ?? "—")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .numericTextTransition()
                    if percent != nil {
                        Text("%").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                if percent != nil {
                    Text(flow.menuWord)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .shadow(color: Color(nsColor: .windowBackgroundColor).opacity(0.6), radius: 3)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        // 用点击而不是拖动：拖动会抢走 ScrollView 的滚动。
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    if let index = index(at: value.location) { onSelect(index) }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent.map { "电量 \($0)%，上限 \(limit)%。时间表在外圈，可以点一段来改。" } ?? "没有电池")
    }

    private var tint: Color {
        guard let percent else { return .secondary }
        switch flow {
        case .charging: return .green
        case .discharging: return percent <= 20 ? .red : (percent <= 40 ? .orange : .accentColor)
        default: return .accentColor
        }
    }

    // MARK: 画

    /// 分钟转成角度：0 点在正上方，顺时针走。
    static func angle(_ minute: Int) -> Angle {
        .degrees(-90 + Double(minute) / 1440 * 360)
    }

    private func drawRing(_ context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - ringWidth / 2
        for block in schedule.blocks {
            let start = Self.angle(block.start)
            let end = Self.angle(block.start + block.length)
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            let color: Color = block.index == nil
                ? .primary.opacity(0.08)
                : .accentColor.opacity(TimelineBar.opacity(for: block.limit))
            context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: ringWidth, lineCap: .butt))
            if let index = block.index, index == selectedIndex {
                var outline = Path()
                outline.addArc(center: center, radius: radius + ringWidth / 2 + 1.5, startAngle: start, endAngle: end, clockwise: false)
                context.stroke(outline, with: .color(.primary), style: StrokeStyle(lineWidth: 2.5, lineCap: .butt))
            }
        }
        // 现在：环上的一个白点，外面描一圈，深浅色都看得见。
        let now = Self.point(center: center, radius: radius, minute: minute)
        let dot = CGRect(x: now.x - 5, y: now.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: dot), with: .color(Color(nsColor: .windowBackgroundColor)))
        context.stroke(Path(ellipseIn: dot.insetBy(dx: 1.5, dy: 1.5)), with: .color(.primary), style: StrokeStyle(lineWidth: 2))
    }

    private static func point(center: CGPoint, radius: CGFloat, minute: Int) -> CGPoint {
        let radians = (-90 + Double(minute) / 1440 * 360) * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(radians)), y: center.y + radius * CGFloat(sin(radians)))
    }

    // MARK: 点

    /// 点在外圈上，就返回那一段的下标；点在圈外或圈内返回 nil。
    private func index(at location: CGPoint) -> Int? {
        let outer = Double(diameter) / 2
        let dx = Double(location.x - diameter / 2)
        let dy = Double(location.y - diameter / 2)
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= outer - Double(ringWidth) - 6, distance <= outer + 4 else { return nil }
        var degrees = atan2(dy, dx) * 180 / .pi + 90
        if degrees < 0 { degrees += 360 }
        if degrees >= 360 { degrees -= 360 }
        let minuteOfTap = Int(degrees / 360 * 1440) % 1440
        return schedule.index(at: minuteOfTap)
    }
}
