import AppKit
import SwiftUI
import BatteryCore

/// 设置：语言、登录、通知、外观、刘海、高级和关于。平时用不到的都收在这里。
struct SettingsView: View {
    @ObservedObject var model: AppModel
    /// 点「完成」：弹窗里换回主页。
    var onClose: () -> Void

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
            if let message = model.message {
                MessageLine(message: message) { model.dismissMessage() }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
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

                Section {
                    Toggle(T("周一到周五停电"), isOn: $model.settings.outageEnabled)
                    // 时间行一直都在，关掉只是变灰。删掉再加回来，系统的时间选择器会跟着列表动画走，画面就花了。
                    // 标题放在行的左边，选择器本身不带标题。以前带标题的选择器把设置页撑宽，两边被裁掉。
                    LabeledContent(T("停电的时间")) {
                        DatePicker("", selection: ClockPicker.binding($model.settings.outageStart),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .fixedSize()
                            .environment(\.locale, ClockPicker.locale)
                    }
                    .disabled(!model.settings.outageEnabled)
                    LabeledContent(T("来电的时间")) {
                        DatePicker("", selection: ClockPicker.binding($model.settings.outageEnd),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .fixedSize()
                            .environment(\.locale, ClockPicker.locale)
                    }
                    .disabled(!model.settings.outageEnabled)
                    if !model.helperUsable {
                        Text(T("低电量模式要放电帮手，在下面「高级」里装一次就行。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .disabled(!model.settings.outageEnabled)
                    }
                } header: {
                    Text(T("工作日停电"))
                } footer: {
                    Text(T("住宿舍、周一到周五这段时间停电时用。停电前会充到你设的目标，停电时开低电量模式省电，来电后关掉。周末在家不停电，照常用主窗口里的设置。"))
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
                    Toggle(T("自动检查新版本"), isOn: $model.settings.autoCheckUpdates)
                    updateRow
                    Button(T("反馈问题")) { model.sendFeedback() }
                    Button(T("再看引导")) { model.replayGuide(); onClose() }
                    Button(T("打开数据文件夹")) { model.openDataFolder() }
                    Link(T("项目主页"), destination: AppInfo.homepage)
                    Text(T("作者 %@", ["\(AppInfo.author)"]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text(Support.personalIntro)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(T("支持这个项目"), destination: Support.personalPage)
                    Link(T("企业合作"), destination: Support.enterprisePage)
                } header: {
                    Text(T("赞助"))
                }
            }
            .formStyle(.grouped)
            // 行的出现和消失不做动画：里面的系统控件（时间、分段、滑块）跟着列表动画走会花。
            .transaction { $0.animation = nil }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var helperRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(T("放电帮手"))
            if model.helperUsable {
                Text(T("已经装好。它负责固定时间表里的放电，也负责停电时的低电量模式。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(T("卸载放电帮手")) { model.removeHelper() }
                    .disabled(model.helperBusy)
            } else {
                Text(T("放电和低电量模式需要它。安装时系统会问一次管理员密码，密码不经过本软件。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(T("安装放电帮手")) { model.installHelper() }
                    .disabled(model.helperBusy)
            }
            if model.helperOutdated {
                Text(T("放电帮手是旧版本：放电和低电量模式要重新安装一次。充电上限不受影响。"))
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
        case .available(let release):
            VStack(alignment: .leading, spacing: 6) {
                Text(T("发现新版本 %@", ["\(release.version)"]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button(T("下载新版本")) { model.openDownload(release) }
                    Button(T("以后再说")) { model.dismissUpdate(release) }
                }
                .controlSize(.small)
            }
        case .relaunching(let version):
            Text(T("新版本 %@ 已经装好，正在重新打开。", ["\(version)"]))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let text):
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.orange)
                HStack(spacing: 8) {
                    Button(T("再试一次")) { model.checkForUpdates(userInitiated: true) }
                    Button(T("去下载页面")) { model.openDownloadPage() }
                }
                .controlSize(.small)
            }
        }
        Button(T("立即检查")) { model.checkForUpdates(userInitiated: true) }
            .disabled(model.update == .checking)
    }
}
