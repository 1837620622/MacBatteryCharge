import AppKit

/// 菜单栏：左边一个按电量填充的电池，右边上下两行小字。整张图是模板图，深色浅色菜单栏都跟着系统变。
enum MenuBarIcon {
    static func image(top: String, bottom: String, level: Double?, charging: Bool) -> NSImage {
        let topAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let bottomAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        let topText = NSAttributedString(string: top, attributes: topAttributes)
        let bottomText = NSAttributedString(string: bottom, attributes: bottomAttributes)
        let textWidth = ceil(max(topText.size().width, bottomText.size().width))
        let glyphWidth: CGFloat = 18
        let gap: CGFloat = 3
        let size = NSSize(width: glyphWidth + gap + textWidth + 1, height: 22)

        let image = NSImage(size: size, flipped: false) { _ in
            drawBattery(in: NSRect(x: 0.5, y: 6.5, width: 15, height: 9), level: level, charging: charging)
            topText.draw(at: NSPoint(x: glyphWidth + gap, y: 10))
            bottomText.draw(at: NSPoint(x: glyphWidth + gap, y: 0.5))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawBattery(in body: NSRect, level: Double?, charging: Bool) {
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let outline = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1
        outline.stroke()
        NSBezierPath(roundedRect: NSRect(x: body.maxX + 1, y: body.midY - 1.75, width: 1.5, height: 3.5), xRadius: 0.75, yRadius: 0.75).fill()

        let inner = body.insetBy(dx: 2, dy: 2)
        let fraction = max(0, min(1, level ?? 0))
        if fraction > 0 {
            var fill = inner
            fill.size.width = max(1.5, inner.width * fraction)
            NSBezierPath(roundedRect: fill, xRadius: 1, yRadius: 1).fill()
        }

        guard charging, let context = NSGraphicsContext.current else { return }
        // 闪电从电池里挖空，背后透出菜单栏的颜色；再描一圈细边，电量低时也看得见。
        let bolt = NSBezierPath()
        let cx = body.midX
        let cy = body.midY
        bolt.move(to: NSPoint(x: cx + 1.2, y: cy + 5.5))
        bolt.line(to: NSPoint(x: cx - 2.8, y: cy - 0.4))
        bolt.line(to: NSPoint(x: cx - 0.2, y: cy - 0.4))
        bolt.line(to: NSPoint(x: cx - 1.2, y: cy - 5.5))
        bolt.line(to: NSPoint(x: cx + 2.8, y: cy + 0.6))
        bolt.line(to: NSPoint(x: cx + 0.2, y: cy + 0.6))
        bolt.close()
        context.saveGraphicsState()
        context.compositingOperation = .destinationOut
        let halo = bolt.copy() as! NSBezierPath
        halo.lineWidth = 2
        halo.stroke()
        context.restoreGraphicsState()
        bolt.fill()
    }
}
