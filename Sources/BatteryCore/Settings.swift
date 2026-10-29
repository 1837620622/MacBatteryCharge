import Foundation

/// 窗口的质感：纯色、磨砂（模糊桌面）、玻璃（系统支持时用 Liquid Glass，否则退回磨砂）。
public enum WindowLook: String, Codable, CaseIterable, Sendable {
    case solid
    case frosted
    case glass

    public var title: String {
        switch self {
        case .solid: return T("纯色")
        case .frosted: return T("磨砂")
        case .glass: return T("玻璃")
        }
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        self = WindowLook(rawValue: text) ?? .frosted
    }
}

/// ~/Library/Application Support/MacBatteryCharge/settings.json。旧版本的文件照样能读，多出来的键直接忽略。
public struct AppSettings: Codable, Equatable, Sendable {
    /// 怎么决定充到多少。默认智能：新装的人最常要的是「随时有电，又别一直满电」。
    public var mode = ChargeMode.smart
    /// 智能模式平时停在哪（80 到 95）。
    public var smartDailyCap = SmartPolicy.defaultDailyCap
    /// 智能模式：记住你平时几点拔电源，离电前自动备电。关掉就只按下面的「默认拔电时间」。
    public var learnHabits = true
    /// 智能模式在学会之前、或者关掉学习时，按这个时间备电。固定模式里是「断电前充满」的时间。
    public var deadlineEnabled = true
    public var deadline = ClockTime(hour: 23, minute: 30)
    /// 离开电源那一刻想有多少电。默认 100%。
    public var unplugTarget = ChargePlanner.defaultTarget
    /// 固定模式的时间段。
    public var intervals: [Interval]
    public var launchAtLogin = true
    public var guideSeen = false
    public var autoCheckUpdates = true
    public var notifications = false
    /// 刘海灵动岛：点一下刘海展开，再点一下收起。关掉就不在刘海上画东西。
    public var notchIsland = true
    /// 插拔电源时从刘海里弹出来，几秒后自己收。
    public var notchOnPower = true
    /// 刘海两侧常驻小字（上限和充电状态）。
    public var notchEars = false
    /// 没有刘海的屏幕上，在菜单栏正中虚拟一个。
    public var notchWithoutNotch = false
    /// 窗口质感和透明度。透明度是窗口底色透出多少桌面，0 不透，最多 0.7。
    public var look = WindowLook.frosted
    public var transparency = 0.25
    public static let transparencyRange = 0.0...0.7
    /// 界面语言。默认跟随系统。
    public var language = AppLanguage.auto
    public var lastUpdateCheck: Date?
    public var skippedVersion: String?
    /// 今天不放电的那一天（yyyy-MM-dd）。只管当天，过了午夜自动失效。
    public var dischargeOffDay: String?

    public init(intervals: [Interval] = Schedule.makeDefaults()) {
        self.intervals = intervals
    }

    enum CodingKeys: String, CodingKey {
        case mode, smartDailyCap, learnHabits
        case intervals, launchAtLogin, guideSeen, autoCheckUpdates, deadlineEnabled, deadline, unplugTarget
        case notifications, lastUpdateCheck, skippedVersion, language
        case notchIsland, notchOnPower, notchEars, notchWithoutNotch
        case look, transparency, dischargeOffDay
    }

    /// 只读 discharge 这一项。旧版本的 lowPower、drift 忽略；旧版本没有放电这一项时，按关处理。
    /// 升级不能把「只限制充电」变成「接着电源也在放电」。
    private struct StoredInterval: Decodable {
        var value: Interval?

        init(from decoder: Decoder) throws {
            value = try? Interval(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.intervals), let stored = try? c.decode([StoredInterval].self, forKey: .intervals) {
            // 用户删光了时间段就保持空的，不偷偷换回默认。
            intervals = stored.compactMap(\.value)
        } else {
            intervals = Schedule.makeDefaults()
        }
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        // 2.x 和 3.0.x 都没有 mode：那些版本的行为就是「按时间表」，所以升级过来是 fixed，
        // 不能悄悄换成智能模式，那是另一种行为。
        let hadMode = c.contains(.mode)
        mode = hadMode ? read(.mode, ChargeMode.smart) : .fixed
        smartDailyCap = SmartPolicy.clampDailyCap(read(.smartDailyCap, SmartPolicy.defaultDailyCap))
        learnHabits = read(.learnHabits, true)
        launchAtLogin = read(.launchAtLogin, true)
        guideSeen = read(.guideSeen, false)
        autoCheckUpdates = read(.autoCheckUpdates, true)
        deadlineEnabled = read(.deadlineEnabled, true)
        deadline = read(.deadline, ClockTime(hour: 23, minute: 30))
        unplugTarget = ChargePlanner.clampTarget(read(.unplugTarget, ChargePlanner.defaultTarget))
        notifications = read(.notifications, false)
        notchIsland = read(.notchIsland, true)
        notchOnPower = read(.notchOnPower, true)
        notchEars = read(.notchEars, false)
        notchWithoutNotch = read(.notchWithoutNotch, false)
        look = read(.look, WindowLook.frosted)
        let rawTransparency = read(.transparency, 0.25)
        transparency = rawTransparency.isFinite ? min(max(rawTransparency, Self.transparencyRange.lowerBound), Self.transparencyRange.upperBound) : 0.25
        language = read(.language, AppLanguage.auto)
        lastUpdateCheck = (try? c.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)) ?? nil
        skippedVersion = (try? c.decodeIfPresent(String.self, forKey: .skippedVersion)) ?? nil
        dischargeOffDay = (try? c.decodeIfPresent(String.self, forKey: .dischargeOffDay)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(smartDailyCap, forKey: .smartDailyCap)
        try c.encode(learnHabits, forKey: .learnHabits)
        try c.encode(intervals, forKey: .intervals)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(guideSeen, forKey: .guideSeen)
        try c.encode(autoCheckUpdates, forKey: .autoCheckUpdates)
        try c.encode(deadlineEnabled, forKey: .deadlineEnabled)
        try c.encode(deadline, forKey: .deadline)
        try c.encode(unplugTarget, forKey: .unplugTarget)
        try c.encode(notifications, forKey: .notifications)
        try c.encode(notchIsland, forKey: .notchIsland)
        try c.encode(notchOnPower, forKey: .notchOnPower)
        try c.encode(notchEars, forKey: .notchEars)
        try c.encode(notchWithoutNotch, forKey: .notchWithoutNotch)
        try c.encode(look, forKey: .look)
        try c.encode(transparency, forKey: .transparency)
        try c.encode(language, forKey: .language)
        try c.encodeIfPresent(lastUpdateCheck, forKey: .lastUpdateCheck)
        try c.encodeIfPresent(skippedVersion, forKey: .skippedVersion)
        try c.encodeIfPresent(dischargeOffDay, forKey: .dischargeOffDay)
    }

    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacBatteryCharge", isDirectory: true)
    }

    public static var defaultURL: URL { directory.appendingPathComponent("settings.json") }
    public static var historyURL: URL { directory.appendingPathComponent("history.json") }
    /// 长期记录（一天一行）。和 72 小时的电量曲线分开存，坏了互不影响。
    public static var journalURL: URL { directory.appendingPathComponent("journal.json") }

    public static func decode(_ data: Data) -> AppSettings? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppSettings.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func load(from url: URL = defaultURL) -> AppSettings {
        guard let data = try? Data(contentsOf: url), let settings = decode(data) else { return AppSettings() }
        return settings
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }
}
