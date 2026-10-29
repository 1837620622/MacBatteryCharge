import SwiftUI
import AppKit
import BatteryCore

/// 第一次打开时的六步引导。每一步上面一小段循环动画，下面是说明。
struct GuideView: View {
    @ObservedObject var model: AppModel
    /// 截图时固定动画位置；正常使用时为 nil。
    var fixedPhase: Double?
    @State private var step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let count = GuideCopy.titles.count

    init(model: AppModel, startStep: Int = 0, fixedPhase: Double? = nil) {
        self.model = model
        self.fixedPhase = fixedPhase
        _step = State(initialValue: startStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 34)
                .padding(.horizontal, 24)

            stage
                .padding(.top, 18)
                .padding(.horizontal, 20)

            dots.padding(.top, 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(step + 1) / \(count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(GuideCopy.titles[step])
                    .font(.title3.weight(.semibold))
                Text(GuideCopy.bodies[step])
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .id(step)
            .transition(.opacity)

            Spacer(minLength: 12)

            buttons
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppGlyph(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(T("欢迎使用充电上限")).font(.title2.weight(.semibold))
                Text(GuideCopy.intro)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var stage: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: fixedPhase != nil || reduceMotion)) { context in
            let phase = fixedPhase ?? (reduceMotion ? 0.8 : Self.phase(at: context.date))
            GuideFrame(step: step, phase: phase)
        }
        .frame(height: 170)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(T("第 %@ 步的示意动画", ["\(step + 1)"]))
    }

    static let period = 2.8

    static func phase(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 7, height: 7)
                    .contentShape(Rectangle().inset(by: -4))
                    .onTapGesture { go(to: index) }
                    .accessibilityLabel(T("第 %@ 步", ["\(index + 1)"]))
                    .accessibilityAddTraits(index == step ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(T("上一步")) { go(to: step - 1) }
                .disabled(step == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])
            Spacer()
            if step < count - 1 {
                Button(T("跳过")) { model.finishGuide() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button(T("下一步")) { go(to: step + 1) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(GuideCopy.finish) { model.finishGuide() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .background {
            // 右方向键也能往下翻。
            Button("") { if step < count - 1 { go(to: step + 1) } }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func go(to index: Int) {
        let target = min(max(index, 0), count - 1)
        guard target != step else { return }
        if reduceMotion {
            step = target
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { step = target }
        }
    }
}

/// 程序图标。装在 .app 里时用真图标，否则画一个电池。
struct AppGlyph: View {
    var size: CGFloat

    var body: some View {
        if Bundle.main.bundleURL.pathExtension == "app" {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: size * 0.84, height: size * 0.84)
                .overlay {
                    Image(systemName: "battery.75percent")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
        }
    }
}

// MARK: 六帧动画

/// phase 从 0 走到 1 再回到 0，一圈 2.8 秒。
struct GuideFrame: View {
    var step: Int
    var phase: Double

    var body: some View {
        switch step {
        case 0: MoveFrame(phase: phase)
        case 1: MenuBarFrame(phase: phase)
        case 2: NotchFrame(phase: phase)
        case 3: PasswordFrame(phase: phase)
        case 4: LimitFrame(phase: phase)
        default: HoldFrame(phase: phase)
        }
    }
}

/// phase 落在 from…to 之间时从 0 平滑走到 1。
func guideProgress(_ phase: Double, from: Double, to: Double) -> Double {
    guard to > from else { return phase >= to ? 1 : 0 }
    let t = min(max((phase - from) / (to - from), 0), 1)
    return t * t * (3 - 2 * t)
}

private struct FrameCaption: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// 一：图标挪进“应用程序”。
private struct MoveFrame: View {
    var phase: Double

    var body: some View {
        let move = guideProgress(phase, from: 0.1, to: 0.55)
        let drop = guideProgress(phase, from: 0.55, to: 0.68)
        let done = guideProgress(phase, from: 0.7, to: 0.8)
        VStack(spacing: 12) {
            ZStack {
                VStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Color.accentColor.opacity(0.85))
                        .scaleEffect(1 + 0.08 * sin(drop * .pi))
                    Text(T("应用程序")).font(.caption).foregroundStyle(.secondary)
                }
                .offset(x: 70)

                AppGlyph(size: 44)
                    .scaleEffect(1 - 0.45 * drop)
                    .opacity(1 - drop)
                    .offset(x: -80 + 150 * move, y: -6 - 8 * sin(move * .pi))

                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .opacity(done)
                    .scaleEffect(0.6 + 0.4 * done)
                    .offset(x: 96, y: -26)
            }
            .frame(height: 96)
            FrameCaption(text: T("拖进去，或者用 PKG 装好"))
        }
    }
}

/// 一小段菜单栏，用真正的菜单栏图标。
private struct MenuBarStrip<Leading: View>: View {
    var top: String
    var bottom: String
    var level: Double
    var charging: Bool
    var highlight: Double = 0
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer(minLength: 0)
            Image(nsImage: MenuBarIcon.image(top: top, bottom: bottom, level: level, charging: charging))
                .renderingMode(.template)
                .foregroundStyle(.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.14 * highlight)))
            Image(systemName: "wifi").font(.system(size: 12, weight: .semibold))
            Text("21:00").font(.system(size: 12, weight: .medium)).monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// 二：上排是上限，下排是状态。
private struct MenuBarFrame: View {
    var phase: Double

    var body: some View {
        let charged = phase >= 0.5
        let click = 1 - abs(phase - 0.5) / 0.08
        VStack(spacing: 0) {
            MenuBarStrip(top: charged ? "100%" : "80%", bottom: charged ? T("充电") : T("接通"),
                         level: charged ? 0.82 : 0.8, charging: charged, highlight: max(0, click)) {
                Image(systemName: "applelogo").font(.system(size: 13))
                Text(T("访达")).font(.system(size: 12, weight: .semibold))
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 18) {
                Label(T("上：现在的上限"), systemImage: "arrow.up")
                Label(T("下：充电 / 放电 / 接通"), systemImage: "arrow.down")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            FrameCaption(text: charged ? T("21:00 起 100%，开始充电") : T("06:00 起 80%，停在上限"))
                .padding(.bottom, 14)
        }
    }
}

/// 三：按住 ⌘ 把图标拖到刘海右边。
private struct NotchFrame: View {
    var phase: Double

    var body: some View {
        let drag = guideProgress(phase, from: 0.2, to: 0.7)
        let holding = phase > 0.12 && phase < 0.78
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Rectangle().fill(.bar).frame(height: 26)
                    .overlay(alignment: .bottom) { Divider() }
                Image(nsImage: MenuBarIcon.image(top: "80%", bottom: T("接通"), level: 0.8, charging: false))
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .frame(height: 26)
                    .offset(x: -20 + 120 * drag)
                    .opacity(holding ? 0.75 : 1)
                // 刘海盖在最上面，图标在它后面时看不见。
                NotchShape(bottomRadius: 10)
                    .fill(Color.black)
                    .frame(width: 120, height: 30)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text("⌘")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(holding ? 0.2 : 0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                    .scaleEffect(holding ? 0.95 : 1)
                Text(T("按住 ⌘ 拖")).font(.callout)
            }
            Spacer(minLength: 0)
            FrameCaption(text: T("放到刘海左边或右边，松手后会记住"))
                .padding(.bottom, 14)
        }
    }
}

/// 四：系统的管理员密码框。
private struct PasswordFrame: View {
    var phase: Double

    var body: some View {
        let typed = Int((guideProgress(phase, from: 0.18, to: 0.6) * 8).rounded())
        let press = phase > 0.68 && phase < 0.8
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 6) {
                    Text(T("充电上限要按这一段的设置修改低电量模式。"))
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 3) {
                        ForEach(0..<8, id: \.self) { index in
                            Circle()
                                .fill(Color.primary)
                                .frame(width: 5, height: 5)
                                .opacity(index < typed ? 1 : 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Text(T("取消"))
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                        Text(T("好"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(press ? 0.7 : 1)))
                            .scaleEffect(press ? 0.94 : 1)
                    }
                }
            }
            .padding(12)
            .frame(width: 270)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            FrameCaption(text: T("系统的密码框，只在这两件事时出现"))
        }
    }
}

/// 五：上限在 80% 和 100% 之间切换。
private struct LimitFrame: View {
    var phase: Double

    var body: some View {
        let high = phase >= 0.5
        let limit = high ? 100 : 80
        let fill = 0.8 + 0.2 * guideProgress(phase, from: 0.5, to: 0.62) - 0.2 * guideProgress(phase, from: 0.94, to: 1)
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(high ? T("21:00 – 次日 06:00") : "06:00 – 21:00")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(limit)%")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 130, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(Color.accentColor).frame(width: geometry.size.width * fill)
                        }
                    }
                    .frame(width: 120, height: 10)
                    HStack(spacing: 4) {
                        ForEach(Schedule.allowedLimits, id: \.self) { value in
                            Text("\(value)")
                                .font(.caption2.weight(value == limit ? .bold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(value == limit ? Color.primary : Color.secondary)
                                .frame(width: 20)
                        }
                    }
                }
            }
            FrameCaption(text: T("只有支持的 Mac 会写上"))
        }
    }
}

/// 六：高于上限时放到上限就停。
private struct HoldFrame: View {
    var phase: Double

    var body: some View {
        let head = guideProgress(phase, from: 0.05, to: 0.9)
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let y: (Double) -> CGFloat = { height * CGFloat(1 - ($0 - 60) / 40) }
                // 92% 一路放到 80%，在 60% 的时间点停住。
                let value: (Double) -> Double = { t in max(80, 92 - 12 * min(1, t / 0.6)) }
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y(80)))
                        path.addLine(to: CGPoint(x: width, y: y(80)))
                    }
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    Text(T("上限 80%"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .offset(x: 4, y: y(80) + 3)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y(value(0))))
                        var t = 0.0
                        while t < head {
                            t += 0.02
                            path.addLine(to: CGPoint(x: width * min(t, head), y: y(value(min(t, head)))))
                        }
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 9, height: 9)
                        .offset(x: width * head - 4.5, y: y(value(head)) - 4.5)
                    Text("\(Int(value(head).rounded()))%")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .offset(x: max(0, width * head - 34), y: y(value(head)) - 22)
                }
            }
            .frame(width: 270, height: 80)
            FrameCaption(text: T("放到 80% 停住，再由电源直接供电"))
        }
    }
}
