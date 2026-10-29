import Foundation
import BatteryCore

/// 检查更新的结果。软件只负责告诉你有新版本，下载和安装由你在发布页完成。
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case failed(String)
}

enum UpdateCheck {
    static let latestURL = URL(string: "https://api.github.com/repos/1837620622/MacFullBar/releases/latest")!

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
