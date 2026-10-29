import SwiftUI
import BatteryCore

/// 有新版本时放在主窗口最上面。下载、等你安装、正在装、没装成，都在这一块说清楚，只给一两个按钮。
struct UpdateBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        switch model.update {
        case .downloading(let release):
            card(title: T("正在下载新版本 %@", ["\(release.version)"]),
                 detail: T("在后台下载，下完会在这里提示你。"),
                 symbol: "arrow.down.circle.fill", tint: .accentColor) {
                Button(T("去下载页面")) { model.openDownloadPage(release) }
                    .controlSize(.small)
            }
        case .ready(let release, _):
            card(title: T("新版本 %@ 已经下好", ["\(release.version)"]),
                 detail: T("点「立即安装」就装上。要输入一次管理员密码；设置和数据都保留，装完会自己重新打开。"),
                 symbol: "checkmark.circle.fill", tint: .green) {
                HStack(spacing: 10) {
                    Button(T("立即安装")) { model.installUpdate() }
                        .buttonStyle(.borderedProminent)
                    Button(T("跳过这个版本")) { model.skip(release) }
                        .controlSize(.small)
                }
            }
        case .installing(let release):
            card(title: T("正在安装 %@", ["\(release.version)"]),
                 detail: T("在弹出的窗口里输入管理员密码。装完会自己重新打开。"),
                 symbol: "gearshape.2.fill", tint: .accentColor) {
                EmptyView()
            }
        case .failed(let text, let release?):
            card(title: T("没能自动更新到 %@", ["\(release.version)"]),
                 detail: text,
                 symbol: "exclamationmark.triangle.fill", tint: .orange) {
                HStack(spacing: 10) {
                    Button(T("去下载页面")) { model.openDownloadPage(release) }
                        .buttonStyle(.borderedProminent)
                    Button(T("再试一次")) { model.downloadUpdate(release) }
                }
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
