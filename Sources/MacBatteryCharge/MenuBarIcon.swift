import AppKit

/// 菜单栏图标：和 App 图标是同一个电池，五格，电量够几格就填几格；右边是百分比，充电时前面带一个闪电。
/// 整张图是模板图，深色浅色菜单栏都跟着系统变。
enum MenuBarIcon {
    static func image(percent: Int?, charging: Bool) -> NSImage {
        let label = NSAttributedString(string: percent.map { "\($0)%" } ?? "—", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.black,
        ])
        let glyph: CGFloat = 22
        let gap: CGFloat = 4
        let boltWidth: CGFloat = charging ? 7 : 0
        let size = NSSize(width: glyph + gap + boltWidth + ceil(label.size().width) + 1, height: 22)

        let image = NSImage(size: size, flipped: false) { _ in
            drawBattery(in: NSRect(x: 0.5, y: 5.5, width: 19, height: 11), level: percent.map { Double($0) / 100 })
            var x = glyph + gap
            if charging {
                drawBolt(centeredAt: NSPoint(x: x + 3, y: size.height / 2))
                x += boltWidth
            }
            label.draw(at: NSPoint(x: x, y: (size.height - label.size().height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 外框、右边一个小凸起、里面五根条。没到的那几格淡一点。
    private static func drawBattery(in body: NSRect, level: Double?) {
        NSColor.black.setStroke()
        let outline = NSBezierPath(roundedRect: body.insetBy(dx: 0.6, dy: 0.6), xRadius: 2.2, yRadius: 2.2)
        outline.lineWidth = 1.2
        outline.stroke()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: body.maxX + 0.8, y: body.midY - 2, width: 1.6, height: 4),
                     xRadius: 0.8, yRadius: 0.8).fill()

        let filled = Int(ceil(max(0, min(1, level ?? 0)) * 5 - 0.001))
        for index in 0..<5 {
            let bar = NSRect(x: body.minX + 2.6 + CGFloat(index) * 2.95, y: body.midY - 2.9, width: 2, height: 5.8)
            NSColor.black.withAlphaComponent(index < filled ? 1 : 0.25).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 0.6, yRadius: 0.6).fill()
        }
    }

    /// 实心闪电，画在百分比前面。
    private static func drawBolt(centeredAt center: NSPoint) {
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: center.x + 1.2, y: center.y + 5.5))
        bolt.line(to: NSPoint(x: center.x - 2.8, y: center.y - 0.4))
        bolt.line(to: NSPoint(x: center.x - 0.2, y: center.y - 0.4))
        bolt.line(to: NSPoint(x: center.x - 1.2, y: center.y - 5.5))
        bolt.line(to: NSPoint(x: center.x + 2.8, y: center.y + 0.6))
        bolt.line(to: NSPoint(x: center.x + 0.2, y: center.y + 0.6))
        bolt.close()
        NSColor.black.setFill()
        bolt.fill()
    }
}
