import XCTest
@testable import BatteryCore

final class LocalizeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Lang.current = .zh
    }

    override func tearDown() {
        Lang.current = .auto
        super.tearDown()
    }

    /// 中文下原样返回。
    func testChinesePassesThrough() {
        Lang.current = .zh
        XCTAssertEqual(T("正在充电"), "正在充电")
    }

    /// 英文下换成词典里的句子。
    func testEnglishLooksUpTable() {
        Lang.current = .en
        XCTAssertEqual(T("正在充电"), Table.english["正在充电"])
        XCTAssertFalse(T("正在充电").isEmpty)
    }

    /// 还没翻译的句子回落中文，不露键名也不留空白。
    func testMissingTranslationFallsBack() {
        Lang.current = .en
        let chinese = "这是一句故意没翻译的话"
        XCTAssertNil(Table.english[chinese])
        XCTAssertEqual(T(chinese), chinese)
    }

    /// 占位符按顺序替换。
    func testPlaceholdersFillInOrder() {
        Lang.current = .zh
        XCTAssertEqual(T("已 %@%", ["80"]), "已 80%")
        XCTAssertEqual(T("%@ – 次日 %@", ["20:00", "06:00"]), "20:00 – 次日 06:00")
    }

    /// 参数比占位符多或少都不能崩。
    func testPlaceholderMismatchIsSafe() {
        Lang.current = .zh
        XCTAssertEqual(T("只有 %@ 一个", ["1", "2", "3"]), "只有 1 一个")
        XCTAssertEqual(T("需要 %@ 和 %@", ["1"]), "需要 1 和 %@")
    }

    /// 跟随系统时看系统语言。
    func testAutoFollowsSystem() {
        Lang.current = .auto
        XCTAssertEqual(Lang.isEnglish, Lang.systemIsEnglish)
    }

    /// 手动指定优先于系统。
    func testManualOverridesSystem() {
        Lang.current = .zh
        XCTAssertFalse(Lang.isEnglish)
        Lang.current = .en
        XCTAssertTrue(Lang.isEnglish)
    }

    /// 词典里的句子不该是空的，也不该还留着中文占位符。
    func testTableIsClean() {
        for (key, value) in Table.english {
            XCTAssertFalse(key.isEmpty)
            XCTAssertFalse(value.isEmpty, "翻译为空：\(key)")
            XCTAssertEqual(value.components(separatedBy: "%@").count, key.components(separatedBy: "%@").count,
                           "占位符数量对不上：\(key)")
        }
    }

    /// 语言要跟着设置存下来。
    func testLanguageRoundTrip() throws {
        var settings = AppSettings()
        XCTAssertEqual(settings.language, .auto)
        settings.language = .en
        let decoded = try XCTUnwrap(AppSettings.decode(settings.encoded()))
        XCTAssertEqual(decoded.language, .en)
        let old = try XCTUnwrap(AppSettings.decode(Data(#"{"intervals":[]}"#.utf8)))
        XCTAssertEqual(old.language, .auto, "老配置没有这一项，跟系统走")
    }
}
