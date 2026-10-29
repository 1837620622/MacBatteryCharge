import SwiftUI
import BatteryCore

// MARK: 放电帮手

struct HelperCard: View {
    @ObservedObject var model: AppModel

    private var summary: String {
        if model.helperOutdated { return "要更新" }
        guard let helper = model.helper else { return "没装" }
        if !helper.adapterControl { return "不支持" }
        return model.discharging ? "放电中" : "已装"
    }

    private var line: String {
        guard let helper = model.helper else { return "没装。装了才能接着电源放电。" }
        if !helper.adapterControl { return "已装，但这台 Mac 断不开电源。" }
        if model.discharging { return "正在放电，到上限就接回电源。" }
        return "已装，待命。"
    }

    var body: some View {
        FoldCard("放电帮手", key: "helper", defaultOpen: model.helper == nil, summary: summary) {
            HStack(spacing: 6) {
                Text(line).font(.callout)
                InfoButton(text: "一个以 root 运行的小程序，需要放电时才断开电源适配器，最低放到 20%。睡眠、退出或 2 分钟没收到软件的指令，都会自己接回电源。只认你这个用户，不联网。Apple 芯片和 Intel 都支持，Intel 用它设 BCLM 上限。")
                Spacer(minLength: 0)
            }
            if let error = model.helper?.error {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
            HStack(spacing: 8) {
                if model.helper == nil || model.helperOutdated {
                    Button(model.helperBusy ? "正在安装…" : (model.helperOutdated ? "更新" : "安装")) { model.installHelper() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.helperBusy || !model.helperInstallable)
                    if !model.helperInstallable {
                        Text("这份软件里没有帮手")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.helper != nil {
                    Button("卸载", role: .destructive) { model.removeHelper() }
                        .disabled(model.helperBusy)
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
    }
}

// MARK: 智能

struct SmartCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FoldCard("智能", key: "smart", defaultOpen: false,
                 summary: model.settings.deadlineEnabled ? "\(model.settings.deadline.text) 断电前充满" : "断电前充满：关") {
            ToggleRow(title: "断电前充满",
                      info: "按这台机器的充电速度，必要时比时间表早放开，赶在断电前充满。只往上放。",
                      isOn: $model.settings.deadlineEnabled)
            if model.settings.deadlineEnabled {
                TimeField(title: "断电", time: $model.settings.deadline)
            }
            Divider()
            ToggleRow(title: "过热保护",
                      info: "接着电源、电池到 35°C 时先停在 80%，降到 33°C 再按时间表。",
                      isOn: $model.settings.heatProtection)
            Divider()
            ToggleRow(title: "通知",
                      info: "停在上限、提前放开、过热时发一条系统通知。打开时才会问通知权限。",
                      isOn: $model.settings.notifications)
        }
    }
}

// MARK: 外观和刘海

struct LookCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FoldCard("外观", key: "look", defaultOpen: false,
                 summary: model.settings.look.title + (model.settings.look == .solid ? "" : " · 透明 \(Int(model.settings.transparency * 100))%")) {
            Picker("质感", selection: $model.settings.look) {
                ForEach(WindowLook.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: 8) {
                Text("透明度")
                Slider(value: $model.settings.transparency, in: AppSettings.transparencyRange)
                Text("\(Int(model.settings.transparency * 100))%")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .disabled(model.settings.look == .solid)
            Divider()
            ToggleRow(title: "刘海灵动岛",
                      info: "鼠标移到刘海上，从刘海里展开电量、上限和今晚的计划。只读鼠标位置，不要任何隐私权限。",
                      isOn: $model.settings.notchIsland)
            ToggleRow(title: "插拔电源时弹出", info: nil, isOn: $model.settings.notchOnPower)
                .disabled(!model.settings.notchIsland)
            ToggleRow(title: "刘海两侧常驻小字",
                      info: "左边是上限，右边是充电、放电或接通。会盖住刘海两边一小块菜单栏。",
                      isOn: $model.settings.notchEars)
            ToggleRow(title: "没有刘海也用",
                      info: "在菜单栏正中虚拟一个，外接显示器和旧款 Mac 也能用。",
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
        case .needsApproval: return "要在系统设置的“登录项”里允许。"
        case .needsApplications: return "放进“应用程序”后才生效。"
        default: return nil
        }
    }

    private var updateText: String? {
        switch model.update {
        case .checking: return "正在查…"
        case .upToDate: return "已是最新"
        case .available(let release): return "有新版本 \(release.version)"
        default: return nil
        }
    }

    var body: some View {
        FoldCard("系统", key: "system", defaultOpen: false, summary: "版本 \(Installation.version)") {
            ToggleRow(title: "登录时打开", info: "只出现在菜单栏，不开窗口。", isOn: $model.settings.launchAtLogin)
            if let loginNote {
                Text(loginNote).font(.caption).foregroundStyle(.secondary)
            }
            if model.loginState == .needsApproval {
                Button("打开登录项设置") { LoginItem.openSystemSettings() }
                    .controlSize(.small)
            }
            ToggleRow(title: "自动检查更新", info: "打开窗口时每天最多查一次。登录时不查，也不弹窗。",
                      isOn: $model.settings.autoCheckUpdates)
            HStack(spacing: 8) {
                Text("版本 \(Installation.version)").foregroundStyle(.secondary).monospacedDigit()
                if let updateText {
                    Text(updateText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("检查更新") { model.checkForUpdates(userInitiated: true) }
                    .disabled(model.update == .checking)
                    .controlSize(.small)
            }
            Divider()
            AboutRow()
            HStack(spacing: 8) {
                Button("再看引导") { model.replayGuide() }
                Spacer()
                Button("复制诊断") { model.copyDiagnostics() }
                Button("卸载…", role: .destructive) { model.uninstall() }
                Button("退出") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
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
                    Text("作者").foregroundStyle(.secondary)
                    Link(AppInfo.author, destination: AppInfo.authorPage)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
            Link(destination: AppInfo.homepage) {
                Label("GitHub", systemImage: "arrow.up.right.square")
                    .font(.caption)
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
                    .accessibilityLabel("关掉这条提示")
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(segmentLine).font(.callout).monospacedDigit().lineLimit(1)
                    Text(model.lowPowerMismatch ? "低电量和系统不同，应用时要密码" : "上限自动写，不要密码")
                        .font(.caption)
                        .foregroundStyle(model.lowPowerMismatch ? Color.orange : Color.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    model.applyNow()
                } label: {
                    HStack(spacing: 6) {
                        if model.applying { ProgressView().controlSize(.small) }
                        Text("立即应用")
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
        let low = model.wantedLowPower == .off ? "不用低电量" : "低电量\(model.wantedLowPower.shortTitle)"
        guard let item = model.currentInterval else { return "空档 100% · \(low)" }
        return "\(item.rangeText) · \(item.limit)% · \(low)"
    }
}
