import SwiftUI
import BatteryCore

/// 电量曲线：过去 16 小时的实线，接上「现在」之后 8 小时的虚线预测。
/// 实线是这台机器记下来的读数；虚线按时间表和充电速度推算，只是估计，底下有一句话说清楚。
struct ChargeCurve: View {
    /// 过去 16 小时的读数，按时间排好。
    var samples: [ChargeSample]
    /// 从现在起的预测。第一个点就是现在的电量。
    var forecast: [ForecastPoint]
    var now: Date

    static let pastMinutes = 16 * 60
    static let futureMinutes = 8 * 60
    /// 两次读数隔得超过这么久，就断开线，不把没记录的那段连起来。
    static let gapMinutes = 20.0
    /// 底下留给时间标签的高度。
    private static let labelHeight: CGFloat = 16

    var body: some View {
        Card {
            Text(T("电量曲线"))
                .font(.headline)
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(height: 96)
            .accessibilityElement()
            .accessibilityLabel(T("过去 16 小时的电量，和之后 8 小时的预测"))
            Text(T("实线是记下来的读数，虚线是按时间表和充电速度推算的，只是估计。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let total = Double(Self.pastMinutes + Self.futureMinutes)
        let plotHeight = size.height - Self.labelHeight
        // 横轴：从 16 小时前到 8 小时后，「现在」在三分之二的地方。纵轴：0 到 100%。
        func x(_ minutes: Double) -> CGFloat { CGFloat((minutes + Double(Self.pastMinutes)) / total) * size.width }
        func y(_ percent: Double) -> CGFloat { plotHeight * (1 - CGFloat(min(100, max(0, percent)) / 100)) }

        for level in [0.0, 50.0, 100.0] {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y(level)))
            line.addLine(to: CGPoint(x: size.width, y: y(level)))
            context.stroke(line, with: .color(.primary.opacity(0.08)), lineWidth: 1)
        }

        var nowLine = Path()
        nowLine.move(to: CGPoint(x: x(0), y: 0))
        nowLine.addLine(to: CGPoint(x: x(0), y: plotHeight))
        context.stroke(nowLine, with: .color(.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        var past = Path()
        var last: Date?
        for sample in samples {
            let minutes = sample.t.timeIntervalSince(now) / 60
            let point = CGPoint(x: x(minutes), y: y(Double(sample.p)))
            if let last, sample.t.timeIntervalSince(last) / 60 <= Self.gapMinutes {
                past.addLine(to: point)
            } else {
                past.move(to: point)
            }
            last = sample.t
        }
        context.stroke(past, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        var future = Path()
        for (index, point) in forecast.enumerated() {
            let place = CGPoint(x: x(Double(point.minutesAhead)), y: y(point.percent))
            if index == 0 { future.move(to: place) } else { future.addLine(to: place) }
        }
        context.stroke(future, with: .color(.accentColor.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 4]))

        // 「现在」的圆点：预测的第一个点就是现在；没有预测时用最后一个读数。
        if let percent = forecast.first?.percent ?? samples.last.map({ Double($0.p) }) {
            let dot = CGRect(x: x(0) - 3.5, y: y(percent) - 3.5, width: 7, height: 7)
            context.fill(Path(ellipseIn: dot), with: .color(.accentColor))
        }

        Self.caption(T("16 小时前"), in: &context, at: CGPoint(x: 0, y: size.height), anchor: .bottomLeading)
        Self.caption(T("现在"), in: &context, at: CGPoint(x: x(0), y: size.height), anchor: .bottom)
        Self.caption(T("之后 8 小时"), in: &context, at: CGPoint(x: size.width, y: size.height), anchor: .bottomTrailing)
    }

    /// 时间标签：小字，灰色。`Text.foregroundStyle` 只有 macOS 14 才有，我们最低支持 13，
    /// 所以先 resolve 成 ResolvedText，再把颜色设在上面。
    private static func caption(_ words: String, in context: inout GraphicsContext, at point: CGPoint, anchor: UnitPoint) {
        var resolved = context.resolve(Text(words).font(.caption2))
        resolved.shading = .color(.secondary)
        context.draw(resolved, at: point, anchor: anchor)
    }
}
