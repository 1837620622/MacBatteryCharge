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
    /// 赞助一节。跟着界面语言走：简体看 README.md，繁体看 README.zh-Hant.md，英文看 README.en.md。
    public static var sponsorPage: URL {
        switch Lang.resolved {
        case .en: return githubFile("README.en.md", anchor: "sponsorship")
        case .zhHant: return githubFile("README.zh-Hant.md", anchor: "贊助")
        default: return githubFile("README.md", anchor: "赞助")
        }
    }
    /// 企业合作的说明，单独一份文档，跟着界面语言走。
    public static var enterprisePage: URL {
        switch Lang.resolved {
        case .en: return githubFile("docs/企业合作.en.md")
        case .zhHant: return githubFile("docs/企業合作.zh-Hant.md")
        default: return githubFile("docs/企业合作.md")
        }
    }

    /// 仓库里的一个文件。路径和锚点都做百分号编码，中文才不会让 URL 解析失败。
    private static func githubFile(_ path: String, anchor: String? = nil) -> URL {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        var text = "https://github.com/\(repository)/blob/main/\(encodedPath)"
        if let anchor {
            text += "#" + (anchor.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? anchor)
        }
        return URL(string: text)!
    }
    /// 新建 issue 的页面，「反馈问题」在它后面带上预填的标题和诊断。
    public static var newIssuePage: URL { URL(string: "https://github.com/\(repository)/issues/new")! }
}
