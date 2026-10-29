import Foundation
import BatteryCore

/// 检查更新的状态。界面只看这个，不自己判断。
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    /// 查到了比现在新的版本。下载和安装都由你来。
    case available(ReleaseInfo)
    /// 新版本已经装在「应用程序」里，旧的正在退出、重新打开新的。
    case relaunching(String)
    /// 查不到新版本。写明原因，设置里给「再试一次」。
    case failed(String)
}

enum UpdateCheck {
    static let latestURL = URL(string: "https://api.github.com/repos/1837620622/MacFullBar/releases/latest")!
    /// 找不到对应芯片的安装包时，去这里看说明、手动下。
    static let releasesPage = URL(string: "https://github.com/1837620622/MacFullBar/releases/latest")!

    /// 本程序是哪种芯片编的，就要哪种安装包。
    static let isArm64: Bool = {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }()

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
