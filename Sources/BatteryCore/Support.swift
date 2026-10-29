import Foundation

/// 赞助和企业合作。设置里「关于」那一块只用这里的文字和链接，别处不要另写一份。
///
/// 支付渠道还没接的时候不要在这里放假链接：宁可只给一个能用的入口，
/// 也不要让用户点进去发现收款码是空的。接好之后只改这一个文件。
public enum Support {
    /// 个人赞助的说明。金额随意，不影响功能。用 `var`：文字要跟着界面语言走。
    public static var personalIntro: String {
        T("充电上限免费、开源，所有功能都不收费。如果你觉得它有用，欢迎自愿赞助，金额随意，不影响任何功能。")
    }

    /// 个人赞助目前走的地方：README 的「赞助」一节。接了赞赏码或爱发电之后换成那边。
    public static var personalPage: URL { AppInfo.sponsorPage }

    /// 企业合作：仓库里的合作说明，写了能谈什么、怎么联系。
    public static var enterprisePage: URL { AppInfo.enterprisePage }
}
