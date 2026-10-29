import AppKit
import SwiftUI
import BatteryCore

/// 设置：语言、登录、通知、外观、刘海、高级和关于。平时用不到的都收在这里。
struct SettingsView: View {
    @ObservedObject var model: AppModel
    /// 点「完成」：弹窗里换回主页。
    var onClose: () -> Void

    private static let issuesURL = URL(string: "https://github.com/1837620622/MacFullBar/issues")!

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(T("设置"))
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 0)
                Button(T("完成")) { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Form {
                Section(T("通用")) {
                    Picker(T("语言"), selection: $model.settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    Toggle(T("登录时打开"), isOn: $model.settings.launchAtLogin)
                    if let note = model.loginNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle(T("备电和过热时通知我"), isOn: $model.settings.notifications)
                }

                Section(T("外观")) {
                    Picker(T("质感"), selection: $model.settings.look) {
                        ForEach(WindowLook.allCases, id: \.self) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    if model.settings.look != .solid {
                        HStack(spacing: 8) {
                            Text(T("透明度"))
                            Slider(value: $model.settings.transparency, in: AppSettings.transparencyRange)
                        }
                    }
                }

                Section {
                    Toggle(T("显示灵动岛"), isOn: $model.settings.notchIsland)
                    Toggle(T("插拔电源时弹出"), isOn: $model.settings.notchOnPower)
                        .disabled(!model.settings.notchIsland)
                    Toggle(T("刘海两侧显示小字"), isOn: $model.settings.notchEars)
                        .disabled(!model.settings.notchIsland)
                    Toggle(T("没有刘海也用（菜单栏正中）"), isOn: $model.settings.notchWithoutNotch)
                } header: {
                    Text(T("刘海灵动岛"))
                } footer: {
                    Text(T("点一下刘海就展开电量和今晚的计划，再点一下收回去。只用鼠标，不需要任何隐私权限。"))
                }

                Section(T("高级")) {
                    helperRow
                    Toggle(T("今天不放电"), isOn: Binding(
                        get: { model.dischargeOffToday },
                        set: { _ in model.toggleDischargeOffToday() }
                    ))
                }

                Section(T("关于")) {
                    LabeledContent(T("版本"), value: Installation.version)
                    Toggle(T("自动检查，并在后台下好新版本"), isOn: $model.settings.autoCheckUpdates)
                    updateRow
                    Button(T("反馈问题")) { NSWorkspace.shared.open(Self.issuesURL) }
                    Button(T("打开数据文件夹")) { model.openDataFolder() }
                    Link(T("项目主页"), destination: AppInfo.homepage)
                    Text(T("作者 %@", ["\(AppInfo.author)"]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var helperRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T("放电帮手"))
            if model.helperUsable {
                Text(T("已经装好。只有固定模式里打开「放电」的时间段会用到它。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(T("卸载放电帮手")) { model.removeHelper() }
                    .disabled(model.helperBusy)
            } else {
                Text(T("只有固定模式里打开「放电」的时间段才需要它。安装时系统会问一次管理员密码，密码不经过本软件。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(T("安装放电帮手")) { model.installHelper() }
                    .disabled(model.helperBusy)
            }
            if model.helperOutdated {
                Text(T("放电帮手是旧版本，重新安装一次。"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var updateRow: some View {
        switch model.update {
        case .idle:
            EmptyView()
        case .checking:
            Text(T("正在查新版本…"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .upToDate:
            Text(T("已经是最新版。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading(let release):
            Text(T("正在下载新版本 %@", ["\(release.version)"]))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .ready(let release, _):
            Text(T("新版本 %@ 已经下好，到窗口里点「立即安装」。", ["\(release.version)"]))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .installing(let release):
            Text(T("正在安装 %@", ["\(release.version)"]))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let text, let release):
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.orange)
                if let release {
                    Button(T("去下载页面")) { model.openDownloadPage(release) }
                        .controlSize(.small)
                }
            }
        }
        Button(T("检查更新")) { model.checkForUpdates(userInitiated: true) }
            .disabled(model.update == .checking)
    }
}
