import SwiftUI
import BatteryCore

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
        // 底色：水没到的那一块也要看得出是个圆盘，不能是白的。
        gc.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.07)))

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

/// 一条会流动的线：圆点沿着线走，方向就是电流的方向。
