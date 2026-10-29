import AppKit
import SwiftUI
import BatteryCore

// MARK: 质感

private struct WindowLookKey: EnvironmentKey {
    static let defaultValue = WindowLook.solid
}

private struct PreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 窗口当前的质感。卡片按它决定怎么画底。
    var windowLook: WindowLook {
        get { self[WindowLookKey.self] }
        set { self[WindowLookKey.self] = newValue }
    }

    /// 截图模式：系统的玻璃和模糊截不下来，用平铺的半透明代替。
    var isPreview: Bool {
        get { self[PreviewKey.self] }
        set { self[PreviewKey.self] = newValue }
    }
}

/// 把桌面模糊后垫在窗口后面。
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// 窗口底。纯色就是系统窗口色；磨砂和玻璃是模糊的桌面，上面再盖一层透明度可调的窗口色。
/// 截图时（preview）画一张假的壁纸代替真正的模糊，让 CI 里也看得出透明的效果。
struct WindowBackdrop: View {
    var look: WindowLook
    var transparency: Double
    var preview = false

    var body: some View {
        switch look {
        case .solid:
            Color(nsColor: .windowBackgroundColor)
        case .frosted, .glass:
            ZStack {
                if preview {
                    PreviewWallpaper()
                } else {
                    VisualEffect()
                }
                Color(nsColor: .windowBackgroundColor).opacity(1 - transparency)
            }
        }
    }
}

/// 只给截图用。
struct PreviewWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.25, green: 0.45, blue: 0.95), Color(red: 0.95, green: 0.45, blue: 0.65),
                                    Color(red: 0.98, green: 0.78, blue: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.white.opacity(0.35)).frame(width: 220).offset(x: -90, y: -160)
            Circle().fill(Color.black.opacity(0.25)).frame(width: 260).offset(x: 110, y: 200)
        }
        .blur(radius: 24)
    }
}

/// 动画的时长统一放在这里，免得各处各写一个数。快的用于选中和切换，标准的用于内容出现和消失。
enum Motion {
    static let quick = Animation.easeInOut(duration: 0.2)
    static let standard = Animation.easeInOut(duration: 0.3)
}

extension View {
    /// 数字变化时滚动过去（macOS 14 起）。更早的系统直接换掉，不影响读数。
    @ViewBuilder
    func numericTextTransition() -> some View {
        if #available(macOS 14, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }

    /// 玻璃卡片：macOS 26 起是系统的 Liquid Glass，更早的系统用超薄材质。
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
    }
}

// MARK: 卡片

/// 一块圆角卡片。底色按窗口质感变：纯色、磨砂用淡淡的前景色，玻璃用系统玻璃。
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @Environment(\.windowLook) private var look
    @Environment(\.isPreview) private var isPreview
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let inner = VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        switch look {
        case .solid:
            inner
                .background(shape.fill(Color.primary.opacity(0.045)))
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5))
        case .frosted:
            inner
                .background(shape.fill(Color.primary.opacity(0.06)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        case .glass:
            if isPreview {
                inner
                    .background(shape.fill(Color.white.opacity(0.16)))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            } else {
                inner.glassSurface()
            }
        }
    }
}
