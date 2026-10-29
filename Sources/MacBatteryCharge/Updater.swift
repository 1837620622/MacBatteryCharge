import Foundation
import BatteryCore

/// 检查和更新的状态。界面只看这个，不自己判断。
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    /// 查到了要装的新版本，正在后台下载并核对安装包。
    case downloading(ReleaseInfo)
    /// 下好了，但现在不能装（正在放电）。条件允许就自动装。
    case waiting(ReleaseInfo, String)
    /// 正在换成新版本。不用密码。
    case installing(ReleaseInfo)
    /// 新版本已经装上，正在退出并重新打开。
    case restarting(ReleaseInfo)
    /// 「应用程序」不让直接换，要一次管理员密码。用户点了按钮才会弹。
    case needsPassword(ReleaseInfo)
    /// 没成功。写明原因，界面给「再试一次」。
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
