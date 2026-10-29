import SwiftUI
import Charts
import BatteryCore

// MARK: 放电帮手

struct HelperCard: View {
    @ObservedObject var model: AppModel

    private var summary: String {
        if model.helperOutdated { return T("要更新") }
        guard let helper = model.helper else { return T("没装") }
        if !helper.adapterControl { return T("不支持") }
        return model.discharging ? T("放电中") : T("已装")
    }

    private var line: String {
        guard let helper = model.helper else { return T("没装。装了才能接着电源放电。") }
        if !helper.adapterControl { return T("已装，但这台 Mac 断不开电源。") }
        if model.discharging { return T("正在放电，到上限就接回电源。") }
        return T("已装，待命。")
    }

    var body: some View {
        FoldCard(T("放电帮手"), key: "helper", defaultOpen: model.helper == nil, summary: summary) {
            HStack(spacing: 6) {
                Text(line).font(.callout)
                InfoButton(text: T("一个以 root 运行的小程序，需要放电时才断开电源适配器，最低放到 20%。睡眠、退出或 2 分钟没收到软件的指令，都会自己接回电源。只认你这个用户，不联网。Apple 芯片和 Intel 都支持，Intel 用它设 BCLM 上限。"))
                Spacer(minLength: 0)
            }
            if let error = model.helper?.error {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
            HStack(spacing: 8) {
                if model.helper == nil || model.helperOutdated {
                    Button(model.helperBusy ? T("正在安装…") : (model.helperOutdated ? T("更新") : T("安装"))) { model.installHelper() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.helperBusy || !model.helperInstallable)
                    if !model.helperInstallable {
                        Text(T("这份软件里没有帮手"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.helper != nil {
                    Button(T("卸载"), role: .destructive) { model.removeHelper() }
                        .disabled(model.helperBusy)
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
    }
}

// MARK: 模式

/// 三选一，选完下面只显示这个模式用得上的东西。
struct ModeCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FoldCard(T("现在用哪个模式"), key: "mode", defaultOpen: true,
                 summary: model.settings.mode.title) {
            Picker(T("模式"), selection: $model.settings.mode) {
                ForEach(ChargeMode.allCases, id: \.self) { mode in
                    VStack(alignment: .leading) {
                        Text(mode.title)
                        Text(mode.tagline).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Text(model.settings.mode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.settings.mode == .smart {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(T("日常上限")).font(.subheadline).foregroundStyle(.secondary)
                        InfoButton(text: T("平时停在这里，不长时间满电。离电前才往上放到离电目标。"))
                    }
                    Picker(T("日常上限"), selection: $model.settings.smartDailyCap) {
                        ForEach(SmartPolicy.dailyCapChoices, id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if let learned = model.learnedUnplug {
                    Label(T("按你平时 %@ 拔电源的习惯提前备电", ["\(learned.text)"]), systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if model.settings.mode != .full, model.settings.deadlineEnabled {
                Divider()
                TimeField(title: T("离电时间"), time: $model.settings.deadline)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(T("离电目标")).font(.subheadline).foregroundStyle(.secondary)
                        InfoButton(text: T("离开电源那一刻想有多少电。和日常上限无关：平时停在 80%，这里照样可以设 100%。"))
                    }
                    Picker(T("离电目标"), selection: $model.settings.unplugTarget) {
                        ForEach(ChargePlanner.targetChoices, id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if model.settings.mode == .fixed {
                Text(T("时间表在下面「时间段」里。放电只在这个模式能用。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: 智能

struct SmartCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FoldCard(T("智能"), key: "smart", defaultOpen: false,
                 summary: model.settings.deadlineEnabled ? T("%@ 前备到 %@%", ["\(model.settings.deadline.text)", "\(model.settings.unplugTarget)"]) : T("离电前备电：关")) {
            ToggleRow(title: T("离电前备到目标电量"),
                      info: T("按这台机器的充电速度，必要时比时间表早放开，赶到离电那一刻有够用的电。只往上放，不会为了这个目标额外放电。"),
                      isOn: $model.settings.deadlineEnabled)
            if model.settings.deadlineEnabled {
                TimeField(title: T("离电时间"), time: $model.settings.deadline)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(T("离电目标")).font(.subheadline).foregroundStyle(.secondary)
                        InfoButton(text: T("离开电源那一刻想有多少电。和上面每一段的日常上限无关：白天停在 80% 的日子，这里照样可以设 100%。默认 100%。"))
                    }
                    Picker(T("离电目标"), selection: $model.settings.unplugTarget) {
                        ForEach(ChargePlanner.targetChoices, id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            Divider()
            ToggleRow(title: T("过热保护"),
                      info: T("接着电源、电池到 35°C 时先停在 80%，降到 33°C 再按时间表。"),
                      isOn: $model.settings.heatProtection)
            Divider()
            ToggleRow(title: T("通知"),
                      info: T("停在上限、提前放开、过热时发一条系统通知。打开时才会问通知权限。"),
                      isOn: $model.settings.notifications)
        }
    }
}

// MARK: 外观和刘海

struct LookCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FoldCard(T("外观"), key: "look", defaultOpen: false,
                 summary: model.settings.look.title + (model.settings.look == .solid ? "" : T(" · 透明 %@%", ["\(Int(model.settings.transparency * 100))"]))) {
            Picker(T("质感"), selection: $model.settings.look) {
                ForEach(WindowLook.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 8) {
                Text(T("透明度"))
                Slider(value: $model.settings.transparency, in: AppSettings.transparencyRange)
                Text("\(Int(model.settings.transparency * 100))%")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .disabled(model.settings.look == .solid)
            Divider()
            ToggleRow(title: T("刘海灵动岛"),
                      info: T("点一下刘海，从刘海里展开电量、上限和今晚的计划，再点一下收回去。只用鼠标，不要任何隐私权限。"),
                      isOn: $model.settings.notchIsland)
            ToggleRow(title: T("插拔电源时弹出"), info: nil, isOn: $model.settings.notchOnPower)
                .disabled(!model.settings.notchIsland)
            ToggleRow(title: T("刘海两侧常驻小字"),
                      info: T("左边是上限，右边是充电、放电或接通。会盖住刘海两边一小块菜单栏。"),
                      isOn: $model.settings.notchEars)
            ToggleRow(title: T("没有刘海也用"),
                      info: T("在菜单栏正中虚拟一个，外接显示器和旧款 Mac 也能用。"),
                      isOn: $model.settings.notchWithoutNotch)
        }
    }
}

// MARK: 系统和关于

struct SystemCard: View {
    @ObservedObject var model: AppModel

    private var loginNote: String? {
        if let note = model.loginNote { return note }
        switch model.loginState {
        case .needsApproval: return T("要在系统设置的“登录项”里允许。")
        case .needsApplications: return T("放进“应用程序”后才生效。")
        default: return nil
        }
    }

    private var updateText: String? {
        switch model.update {
        case .checking: return T("正在查…")
        case .upToDate: return T("已是最新")
        case .available(let release): return T("有新版本 %@", ["\(release.version)"])
        default: return nil
        }
    }

    var body: some View {
        FoldCard(T("系统"), key: "system", defaultOpen: false, summary: T("版本 %@", ["\(Installation.version)"])) {
            ToggleRow(title: T("登录时打开"), info: T("只出现在菜单栏，不开窗口。"), isOn: $model.settings.launchAtLogin)
            if let loginNote {
                Text(loginNote).font(.caption).foregroundStyle(.secondary)
            }
            if model.loginState == .needsApproval {
                Button(T("打开登录项设置")) { LoginItem.openSystemSettings() }
                    .controlSize(.small)
            }
            ToggleRow(title: T("自动检查更新"), info: T("打开窗口时每天最多查一次。登录时不查，也不弹窗。"),
                      isOn: $model.settings.autoCheckUpdates)
            HStack(spacing: 8) {
                Text(T("版本 %@", ["\(Installation.version)"])).foregroundStyle(.secondary).monospacedDigit()
                if let updateText {
                    Text(updateText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(T("检查更新")) { model.checkForUpdates(userInitiated: true) }
                    .disabled(model.update == .checking)
                    .controlSize(.small)
            }
            Divider()
            AboutRow()
            HStack(spacing: 8) {
                Button(T("再看引导")) { model.replayGuide() }
                Button(T("反馈问题")) { model.reportIssue() }
                    .help(T("会带上诊断信息和最近的日志，打开提 issue 的页面。"))
                Spacer()
                Menu(T("更多")) {
                    Button(T("复制诊断")) { model.copyDiagnostics() }
                    Button(T("复制 issue 正文")) { model.copyIssueBody() }
                    Button(T("打开日志")) { Log.openLogFolder() }
                    Button(T("数据文件夹")) { model.openDataFolder() }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button(T("卸载…"), role: .destructive) { model.uninstall() }
                Button(T("退出")) { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
    }
}

// MARK: 记录和提醒

/// 长期记录。像健康 App 那样，一天一行，看最近的走势。
struct JournalCard: View {
    @ObservedObject var model: AppModel

    private static let weeks = 14

    var body: some View {
        FoldCard(T("记录"), key: "journal", defaultOpen: false, summary: summary) {
            if model.journal.days.isEmpty {
                Text(T("用几天就会有记录。每天一行，存在这台 Mac 上，不上传。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(T("每天一行，存在这台 Mac 上，不上传。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                chart
                HStack(spacing: 10) {
                    legend(color: .teal, text: T("接电源"))
                    legend(color: .orange, text: T("用电池"))
                    Spacer(minLength: 0)
                }
                if !model.tips.isEmpty {
                    Divider()
                    ForEach(model.tips) { tip in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: tip.symbol)
                                .foregroundStyle(.teal)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tip.title).font(.callout.weight(.medium))
                                Text(tip.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    Button(T("打开数据文件夹")) { model.openDataFolder() }
                        .controlSize(.small)
                    Spacer(minLength: 0)
                    Text(T("共 %@ 天", ["\(model.journal.days.count)"]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var summary: String {
        guard let today = model.journal.today else { return T("还没有记录") }
        return T("%@ 天 · 今天 %@", ["\(model.journal.days.count)", today.hi.map { "\($0)%" } ?? "—"])
    }

    /// 一天一根柱子：上面接电源的时长，下面用电池的时长。
    private var chart: some View {
        let days = model.journal.daysBack(Self.weeks)
        let peak: Double = max(1, days.map { $0.batteryHours + $0.powerHours }.max() ?? 1)
        return Chart {
            ForEach(days, id: \.day) { day in
                BarMark(x: .value(T("日期"), String(day.day.suffix(5))), y: .value(T("接电源"), day.powerHours))
                    .foregroundStyle(Color.teal.opacity(0.55))
                BarMark(x: .value(T("日期"), String(day.day.suffix(5))), y: .value(T("用电池"), day.batteryHours))
                    .foregroundStyle(Color.orange.opacity(0.7))
            }
        }
        .chartYScale(domain: 0...max(8, peak.rounded(.up)))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 90)
        .accessibilityLabel(T("最近 %@ 天里每天接电源和用电池的小时数", ["\(days.count)"]))
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: 语言

struct LanguageCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FoldCard(T("语言"), key: "language", defaultOpen: false, summary: model.settings.language.title) {
            Picker(T("语言"), selection: $model.settings.language) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(T("改完立刻生效。还没翻译的句子会先显示中文，不会显示成空白。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: 支持

/// 个人赞助和企业合作分成两个入口。个人这边是自愿的、金额随意的；
/// 企业那边是能谈的几件事，单独一页，不混在日常使用流程里。
struct SupportCard: View {
    var body: some View {
        FoldCard(T("支持这个项目"), key: "support", defaultOpen: false, summary: T("赞助 · 企业合作")) {
            Text(Support.personalIntro)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Link(destination: Support.personalPage) {
                    Label(T("个人赞助"), systemImage: "heart")
                        .font(.callout)
                }
                Spacer(minLength: 0)
            }
            Text(T("赞助是自愿的，不影响任何功能，也不会因此弹窗打扰你。"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text(Support.enterpriseIntro)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Support.enterpriseItems, id: \.title) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.callout.weight(.medium))
                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Link(destination: Support.enterprisePage) {
                    Label(T("企业合作说明"), systemImage: "building.2")
                        .font(.callout)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// 作者和项目。
struct AboutRow: View {
    var body: some View {
        HStack(spacing: 10) {
            AppGlyph(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(AppInfo.name) \(Installation.version)").font(.callout.weight(.semibold))
                HStack(spacing: 4) {
                    Text(T("作者")).foregroundStyle(.secondary)
                    Link(AppInfo.author, destination: AppInfo.authorPage)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Link(destination: AppInfo.sponsorPage) {
                    Label(T("赞助"), systemImage: "heart")
                        .font(.caption)
                }
                Link(destination: AppInfo.homepage) {
                    Label("GitHub", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: 底部

struct FooterBar: View {
    @ObservedObject var model: AppModel

    private var tint: Color {
        switch model.message?.tone {
        case .success?: return .green
        case .error?: return .red
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = model.message {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: message.tone == .error ? "exclamationmark.circle.fill" : (message.tone == .success ? "checkmark.circle.fill" : "info.circle.fill"))
                        .foregroundStyle(tint)
                    Text(message.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        model.dismissMessage()
                    } label: {
                        Image(systemName: "xmark").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(T("关掉这条提示"))
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(segmentLine).font(.callout).monospacedDigit().lineLimit(1)
                    Text(model.lowPowerMismatch ? T("低电量和系统不同，应用时要密码") : T("上限自动写，不要密码"))
                        .font(.caption)
                        .foregroundStyle(model.lowPowerMismatch ? Color.orange : Color.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    model.applyNow()
                } label: {
                    HStack(spacing: 6) {
                        if model.applying { ProgressView().controlSize(.small) }
                        Text(T("立即应用"))
                    }
                    .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.applying)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var segmentLine: String {
        let low = model.wantedLowPower == .off ? T("不用低电量") : T("低电量%@", ["\(model.wantedLowPower.shortTitle)"])
        guard let item = model.currentInterval else { return T("空档 100% · %@", ["\(low)"]) }
        return "\(item.rangeText) · \(item.limit)% · \(low)"
    }
}
