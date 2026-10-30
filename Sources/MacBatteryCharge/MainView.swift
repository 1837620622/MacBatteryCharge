import AppKit
import SwiftUI
import BatteryCore

/// 主窗口：上面是现在的电量和正在做什么，中间是三种模式，下面是临时充满。
/// 其它设置收进右上角的齿轮。
struct RootView: View {
    /// 弹窗里的页面：主页，或者设置。第一次的引导由 model.showGuide 决定，盖在最上面。
    enum Page { case main, settings }

    /// 菜单栏弹窗的大小。
    static let popoverSize = NSSize(width: 400, height: 680)

    @ObservedObject var model: AppModel
    @State private var page: Page

    init(model: AppModel, page: Page = .main) {
        self.model = model
        _page = State(initialValue: page)
    }

    var body: some View {
        ZStack {
            WindowBackdrop(look: model.settings.look, transparency: model.settings.transparency)
            if model.showGuide {
                // 引导的内容短，上下居中，不留一大片空白。
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    GuideView(model: model)
                    Spacer(minLength: 0)
                }
            } else if page == .settings {
                SettingsView(model: model) { switchPage(.main) }
                    .transition(.opacity)
            } else {
                mainPage
                    .transition(.opacity)
            }
        }
    }

    /// 主页和设置之间淡入淡出，不硬切。
    private func switchPage(_ next: Page) {
        withAnimation(Motion.quick) { page = next }
    }

    private var mainPage: some View {
        VStack(spacing: 0) {
            header
            // 内容放得下就不滚动，曲线占满剩下的高度；放不下才滚动，曲线保持原来的高度。
            ViewThatFits(in: .vertical) {
                pageBody(fillsHeight: true)
                ScrollView {
                    pageBody(fillsHeight: false)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func pageBody(fillsHeight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let message = model.message {
                MessageLine(message: message) { model.dismissMessage() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            // 时间表有错要改好才会消失，所以这一行没有「关掉」。
            if let error = model.scheduleError {
                MessageLine(message: AppModel.Message(tone: .error, text: error.message))
            }
            UpdateBanner(model: model)
            tonightCard
            curve(fillsHeight: fillsHeight)
            ChoiceBar(options: ChargeMode.allCases, title: { $0.title }, selection: modeBinding)
            Text(model.settings.mode.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
            modePanel
            // 一直充满本来就是 100%，临时充满没有用，也就不放这一行。
            if model.settings.mode != .full {
                footer
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        .animation(Motion.standard, value: model.message)
        .animation(Motion.standard, value: model.tonight)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                LiquidDisc(level: Double(model.battery.percent ?? 0) / 100, limit: model.decision.limit,
                           tint: ringColor, flow: model.displayFlow, live: model.liveMotion)
                    .frame(width: 96, height: 96)
                    .animation(.easeInOut(duration: 0.8), value: model.battery.percent)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                Text(percentText)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .numericTextTransition()
                    .shadow(color: .black.opacity(0.25), radius: 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(diskLabel)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.statusTitle)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                Text(model.statusDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.modeDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                switchPage(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.top, 2)
            }
            .buttonStyle(.plain)
            .help(T("设置"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    /// 今晚的计划放在最上面：这是人最想知道的一句话，不用在别处找。
    /// 电量曲线：过去 16 小时和之后 8 小时的预测。还没有读数时不占地方。
    @ViewBuilder private func curve(fillsHeight: Bool) -> some View {
        let samples = model.history.samples(since: Date().addingTimeInterval(-TimeInterval(ChargeCurve.pastMinutes * 60)))
        if !samples.isEmpty {
            ChargeCurve(samples: samples, forecast: model.forecast, now: Date(), fills: fillsHeight)
        }
    }

    @ViewBuilder private var tonightCard: some View {
        if let tonight = model.tonight {
            let tint = tonightTint(tonight.tone)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tonight.symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tonight.title)
                        .font(.headline)
                    Text(tonight.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.1)))
            .accessibilityElement(children: .combine)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func tonightTint(_ tone: AppModel.Message.Tone) -> Color {
        switch tone {
        case .info: return .accentColor
        case .success: return .green
        case .error: return .orange
        }
    }

    @ViewBuilder private var modePanel: some View {
        Group {
            switch model.settings.mode {
            case .smart:
                SmartPanel(model: model)
            case .fixed:
                FixedPanel(model: model)
            case .full:
                FullPanel()
            }
        }
        .id(model.settings.mode)
        .transition(.opacity)
    }

    /// 临时充满旁边那句话：固定模式说「这一段」，智能说「拔掉电源」。
    private var topUpHint: String {
        let fixed = model.settings.mode == .fixed
        if model.topUpActive { return fixed ? T("到下一段或拔掉电源时结束") : T("拔掉电源时结束") }
        return fixed ? T("这一段先充到 100%，拔掉电源时结束") : T("先充到 100%，拔掉电源时结束")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleTopUp()
            } label: {
                Label(model.topUpActive ? T("结束临时充满") : T("临时充满"), systemImage: "bolt.fill")
            }
            .disabled(!model.topUpAvailable)
            Text(topUpHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var modeBinding: Binding<ChargeMode> {
        Binding(get: { model.settings.mode }, set: { mode in
            withAnimation(Motion.standard) { model.settings.mode = mode }
        })
    }

    private var percentText: String {
        model.battery.percent.map { "\($0)%" } ?? "—"
    }

    /// 给 VoiceOver 读的一句：电量和现在的状态。
    private var diskLabel: String {
        model.battery.percent.map { T("电量 %@%，%@", ["\($0)", model.statusTitle]) } ?? model.statusTitle
    }

    private var ringColor: Color {
        switch model.displayFlow {
        case .charging: return .green
        case .discharging: return (model.battery.percent ?? 100) <= 20 ? .red : .orange
        default: return .accentColor
        }
    }
}

/// 一行提示：出错、写上限失败、时间表有问题都从这里说。
struct MessageLine: View {
    var message: AppModel.Message
    /// 有「关掉」动作才显示 ×。
    var dismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(message.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(T("关掉这条提示"))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.12)))
    }

    private var symbol: String {
        switch message.tone {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch message.tone {
        case .info: return .accentColor
        case .success: return .green
        case .error: return .orange
        }
    }
}

/// 时间和 Date 互相转换，给 DatePicker 用。只用到小时和分钟。
enum ClockPicker {
    static func date(_ time: ClockTime) -> Date {
        var parts = DateComponents()
        parts.hour = time.hour
        parts.minute = time.minute
        return Calendar.current.date(from: parts) ?? Date()
    }

    static func clock(_ date: Date) -> ClockTime {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    static func binding(_ time: Binding<ClockTime>) -> Binding<Date> {
        Binding(get: { date(time.wrappedValue) }, set: { time.wrappedValue = clock($0) })
    }

    /// 时间选择器的语言跟着界面语言走，不跟着系统。系统是英文、界面是中文时，时间也不该显示成 AM/PM。
    static var locale: Locale {
        switch Lang.resolved {
        case .zh: return Locale(identifier: "zh_CN")
        case .zhHant: return Locale(identifier: "zh_TW")
        case .en, .auto: return Locale(identifier: "en_US")
        }
    }
}
