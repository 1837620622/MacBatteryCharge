import Foundation

/// 赞助和企业合作。窗口里「支持」页只用这里的文字和链接，别处不要另写一份。
///
/// 支付渠道还没接的时候不要在这里放假链接：宁可只给一个能用的入口，
/// 也不要让用户点进去发现收款码是空的。接好之后只改这一个文件。
public enum Support {
    /// 个人赞助的说明。金额随意，不影响功能。
    public static let personalIntro = """
    充电上限免费、开源，所有功能都不收费，以后也不会对个人收费。
    如果你觉得它有用，欢迎自愿赞助，金额随意。
    """

    /// 企业合作能谈什么。写具体，别写“欢迎洽谈”四个字就完事。
    public static let enterpriseIntro = """
    企业赞助、定制开发和技术支持可以单独谈。
    """

    public static var enterpriseItems: [(title: String, detail: String)] { [
        (T("企业赞助"), T("在 README 的赞助名单里列出公司名称和链接，可以放在软件「关于」里。")),
        (T("定制开发"), T("按你们的环境改：批量部署、内部时间表策略、和现有运维系统对接。")),
        (T("技术支持"), T("为团队里的 Mac 统一设充电策略，回答部署和权限上的问题。")),
    ] }

    /// 个人赞助目前走的地方：README 的赞助一节。接了赞赏码或爱发电之后换成那边。
    public static var personalPage: URL { AppInfo.sponsorPage }

    /// 企业合作：仓库里的合作说明，写了能谈什么、怎么联系。
    public static var enterprisePage: URL { AppInfo.enterprisePage }
}
