import SwiftUI
import BatteryCore

/// 有新版本时放在主窗口最上面。下载、安装、重新打开都是自动的，这里只说清楚现在在做什么；
/// 要你做点什么的时候（「应用程序」不让直接换、或者没成功）才给按钮。
struct UpdateBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        switch model.update {
        case .downloading(let release):
            card(title: T("正在下载新版本 %@", ["\(release.version)"]),
                 detail: T("在后台下载，下完会自动装上，不用管它。"),
                 symbol: "arrow.down.circle.fill", tint: .accentColor) {
                ProgressView().controlSize(.small)
            }
        case .waiting(let release, let reason):
            card(title: T("新版本 %@ 已经下好", ["\(release.version)"]),
                 detail: reason,
                 symbol: "clock.fill", tint: .orange) {
                EmptyView()
            }
        case .installing(let release):
            card(title: T("正在换成新版本 %@", ["\(release.version)"]),
                 detail: T("设置和数据都保留。装完会自己重新打开，不用重启电脑。"),
                 symbol: "gearshape.2.fill", tint: .accentColor) {
                ProgressView().controlSize(.small)
            }
        case .restarting(let release):
            card(title: T("新版本 %@ 已经装好", ["\(release.version)"]),
                 detail: T("正在重新打开。"),
                 symbol: "checkmark.circle.fill", tint: .green) {
                EmptyView()
            }
        case .needsPassword(let release):
            card(title: T("新版本 %@ 已经下好", ["\(release.version)"]),
                 detail: T("「应用程序」不让直接换，需要输入一次管理员密码。设置和数据都保留。"),
                 symbol: "lock.fill", tint: .orange) {
                Button(T("输入密码，装上新版本")) { model.installWithPassword() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        case .failed(let text, let release?):
            card(title: T("没能更新到 %@", ["\(release.version)"]),
                 detail: text,
                 symbol: "exclamationmark.triangle.fill", tint: .orange) {
                Button(T("再试一次")) { model.downloadUpdate(release) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        default:
            EmptyView()
        }
    }

    private func card<Actions: View>(title: String, detail: String, symbol: String, tint: Color,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.1)))
        .accessibilityElement(children: .contain)
    }
}
