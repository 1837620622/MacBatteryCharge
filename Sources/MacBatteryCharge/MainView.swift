import AppKit
import SwiftUI
import BatteryCore

/// 主窗口：上面是现在的电量和正在做什么，中间是三种模式，下面是临时充满。
/// 其它设置收进右上角的齿轮。
struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false

    var body: some View {
        ZStack {
            WindowBackdrop(look: model.settings.look, transparency: model.settings.transparency)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let message = model.message {
                            MessageLine(message: message) { model.dismissMessage() }
                        }
                        if let error = model.scheduleError {
                            MessageLine(message: AppModel.Message(tone: .error, text: error.message)) {}
                        }
                        UpdateBanner(model: model)
                        tonightCard
                        Picker(T("模式"), selection: modeBinding) {
                            ForEach(ChargeMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(model.settings.mode.tagline)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        modePanel
                        footer
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        .sheet(isPresented: $model.showGuide) {
            GuideView(model: model)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                LiquidDisc(level: Double(model.battery.percent ?? 0) / 100, limit: model.decision.limit,
                           tint: ringColor, flow: model.displayFlow, live: model.liveMotion)
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                Text(percentText)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.25), radius: 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(diskLabel)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.statusTitle)
                    .font(.title3.weight(.semibold))
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
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .help(T("设置"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    /// 今晚的计划放在最上面：这是人最想知道的一句话，不用在别处找。
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
        switch model.settings.mode {
        case .smart:
            SmartPanel(model: model)
        case .fixed:
            FixedPanel(model: model)
        case .full:
            FullPanel()
        }
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
        Binding(get: { model.settings.mode }, set: { model.settings.mode = $0 })
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
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(message.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(T("关掉这条提示"))
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
