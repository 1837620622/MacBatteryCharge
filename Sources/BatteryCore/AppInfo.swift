import Foundation

/// 作者和项目信息。窗口里的“关于”、关于面板、README 都用这里的。
public enum AppInfo {
    public static var name: String { T("充电上限") }
    public static var author: String { T("传康Kk") }
    public static let githubUser = "1837620622"
    public static let repository = "1837620622/MacFullBar"
    public static var copyright: String { T("© 2026 传康Kk") }

    public static var homepage: URL { URL(string: "https://github.com/\(repository)")! }
    public static var authorPage: URL { URL(string: "https://github.com/\(githubUser)")! }
    public static var releasesPage: URL { URL(string: "https://github.com/\(repository)/releases")! }
    /// README 里的「赞助」一节。锚点写成百分号编码，免得中文让 URL 解析失败。
    public static var sponsorPage: URL { URL(string: "https://github.com/\(repository)/blob/main/README.md#%E8%B5%9E%E5%8A%A9")! }
    /// 企业的合作说明，单独一份文档，不和个人赞助挤在一起。
    public static var enterprisePage: URL {
        URL(string: "https://github.com/\(repository)/blob/main/docs/%E4%BC%81%E4%B8%9A%E5%90%88%E4%BD%9C.md")!
    }
    /// 新建 issue 的页面，「反馈问题」在它后面带上预填的标题和诊断。
    public static var newIssuePage: URL { URL(string: "https://github.com/\(repository)/issues/new")! }
}
