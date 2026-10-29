import Foundation

/// 作者和项目信息。窗口里的“关于”、关于面板、README 都用这里的。
public enum AppInfo {
    public static let name = "充电上限"
    public static let author = "传康Kk"
    public static let githubUser = "1837620622"
    public static let repository = "1837620622/MacBatteryCharge"
    public static let copyright = "© 2026 传康Kk"

    public static var homepage: URL { URL(string: "https://github.com/\(repository)")! }
    public static var authorPage: URL { URL(string: "https://github.com/\(githubUser)")! }
    public static var releasesPage: URL { URL(string: "https://github.com/\(repository)/releases")! }
}
