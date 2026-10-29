import Foundation
import BatteryCore

/// 检查和更新的状态。界面只看这个，不自己判断。
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    /// 查到了要装的新版本，正在后台下载并核对安装包。
    case downloading(ReleaseInfo)
    /// 下好了、核对过，等你点一下「立即安装」。
    case ready(ReleaseInfo, URL)
    /// 安装器在跑，会弹一次管理员密码框。
    case installing(ReleaseInfo)
    /// 没成功。有版本信息时，界面给一个去下载页面的跳转。
    case failed(String, ReleaseInfo?)
}

enum UpdateCheck {
    static let latestURL = URL(string: "https://api.github.com/repos/1837620622/MacFullBar/releases/latest")!
    /// 自动更新没成功时，跳到这里手动下。
    static let releasesPage = URL(string: "https://github.com/1837620622/MacFullBar/releases/latest")!

    static func fetchLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("MacFullBar/\(Installation.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError(T("GitHub 没有返回版本信息"))
        }
        guard let release = ReleaseInfo.parse(data) else { throw UpdateError(T("版本信息看不懂")) }
        return release
    }
}

struct UpdateError: LocalizedError {
    var text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}
