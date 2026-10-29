import Foundation

/// ~/Library/Application Support/MacBatteryCharge/settings.json，和 2.x 同一个文件，键名兼容。
public struct AppSettings: Codable, Equatable, Sendable {
    public var intervals: [Interval]
    public var launchAtLogin = true
    public var guideSeen = false
    public var autoCheckUpdates = true
    /// 每天断电的时间。开着时会在断电前按速度提前放开到时间表的值。
    public var deadlineEnabled = true
    public var deadline = ClockTime(hour: 23, minute: 30)
    public var heatProtection = true
    public var notifications = false
    public var lastUpdateCheck: Date?
    public var skippedVersion: String?

    public init(intervals: [Interval] = Schedule.makeDefaults()) {
        self.intervals = intervals
    }

    enum CodingKeys: String, CodingKey {
        case intervals, launchAtLogin, guideSeen, autoCheckUpdates, deadlineEnabled, deadline
        case heatProtection, notifications, lastUpdateCheck, skippedVersion
        case lowPowerAuto
    }

    /// 2.0 存的时间段没有 lowPower，全局的 lowPowerAuto 打开时按「仅用电池时开」。
    private struct StoredInterval: Decodable {
        var value: Interval?
        var hadLowPower = false

        init(from decoder: Decoder) throws {
            value = try? Interval(from: decoder)
            if let keyed = try? decoder.container(keyedBy: Interval.CodingKeys.self) {
                hadLowPower = keyed.contains(.lowPower)
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyAuto = (try? c.decodeIfPresent(Bool.self, forKey: .lowPowerAuto)) ?? false
        if c.contains(.intervals), let stored = try? c.decode([StoredInterval].self, forKey: .intervals) {
            // 用户删光了时间段就保持空的，不偷偷换回默认。
            intervals = stored.compactMap { item in
                guard var value = item.value else { return nil }
                if !item.hadLowPower && legacyAuto { value.lowPower = .battery }
                return value
            }
        } else {
            intervals = Schedule.makeDefaults()
        }
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        launchAtLogin = read(.launchAtLogin, true)
        guideSeen = read(.guideSeen, false)
        autoCheckUpdates = read(.autoCheckUpdates, true)
        deadlineEnabled = read(.deadlineEnabled, true)
        deadline = read(.deadline, ClockTime(hour: 23, minute: 30))
        heatProtection = read(.heatProtection, true)
        notifications = read(.notifications, false)
        lastUpdateCheck = (try? c.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)) ?? nil
        skippedVersion = (try? c.decodeIfPresent(String.self, forKey: .skippedVersion)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(intervals, forKey: .intervals)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(guideSeen, forKey: .guideSeen)
        try c.encode(autoCheckUpdates, forKey: .autoCheckUpdates)
        try c.encode(deadlineEnabled, forKey: .deadlineEnabled)
        try c.encode(deadline, forKey: .deadline)
        try c.encode(heatProtection, forKey: .heatProtection)
        try c.encode(notifications, forKey: .notifications)
        try c.encodeIfPresent(lastUpdateCheck, forKey: .lastUpdateCheck)
        try c.encodeIfPresent(skippedVersion, forKey: .skippedVersion)
    }

    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacBatteryCharge", isDirectory: true)
    }

    public static var defaultURL: URL { directory.appendingPathComponent("settings.json") }
    public static var historyURL: URL { directory.appendingPathComponent("history.json") }

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
