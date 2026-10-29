import SwiftUI
import BatteryCore

/// 有新版本时放在主窗口最上面：提示你，由你点「下载新版本」自己装。装上以后，旧版本会自己重新打开。
struct UpdateBanner: View {
    @ObservedObject var model: AppModel

    var body: some View {
        switch model.update {
        case .available(let release):
            card(title: T("发现新版本 %@", ["\(release.version)"]),
                 detail: T("下载和安装都由你来：点「下载新版本」，在浏览器里下对应芯片的安装包，打开它就能装。装完旧版本会自己重新打开，设置和数据都保留。"),
                 symbol: "arrow.down.circle.fill", tint: .accentColor) {
                HStack(spacing: 10) {
                    Button(T("下载新版本")) { model.openDownload(release) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button(T("以后再说")) { model.dismissUpdate(release) }
                        .controlSize(.small)
                }
            }
        case .relaunching(let version):
            card(title: T("新版本 %@ 已经装好", ["\(version)"]),
                 detail: T("正在重新打开。"),
                 symbol: "checkmark.circle.fill", tint: .green) {
                EmptyView()
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
