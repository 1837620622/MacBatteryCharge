import Foundation

/// 一个电量采样。键名短，文件小。
public struct ChargeSample: Codable, Equatable, Sendable {
    public var t: Date
    /// 电量 %
    public var p: Int
    /// 正在充电
    public var c: Bool
    /// 接着电源
    public var x: Bool
    /// 当时的上限
    public var l: Int

    public init(t: Date, p: Int, c: Bool, x: Bool, l: Int) {
        self.t = t
        self.p = p
        self.c = c
        self.x = x
        self.l = l
    }
}

/// 每天一条健康度。
public struct HealthPoint: Codable, Equatable, Sendable {
    public var day: String
    public var health: Int
    public var cycles: Int?

    public init(day: String, health: Int, cycles: Int?) {
        self.day = day
        self.health = health
        self.cycles = cycles
    }
}

public struct ChargeHistory: Codable, Equatable, Sendable {
    public static let keep: TimeInterval = 72 * 3600
    public static let minGap: TimeInterval = 4 * 60

    public var samples: [ChargeSample] = []
    public var health: [HealthPoint] = []

    public init() {}

    /// 四分钟最多一条；电量、电源或上限变了就马上记。
    public mutating func add(_ sample: ChargeSample) {
        if let last = samples.last {
            let gap = sample.t.timeIntervalSince(last.t)
            let changed = last.p != sample.p || last.x != sample.x || last.l != sample.l
            if gap >= 0 && gap < Self.minGap && !changed { return }
            if gap < 0 { samples.removeAll { $0.t >= sample.t } }
        }
        samples.append(sample)
        let cutoff = sample.t.addingTimeInterval(-Self.keep)
        if let first = samples.firstIndex(where: { $0.t >= cutoff }), first > 0 {
            samples.removeFirst(first)
        }
    }

    public mutating func addHealth(_ point: HealthPoint) {
        if let index = health.firstIndex(where: { $0.day == point.day }) {
            health[index] = point
        } else {
            health.append(point)
            if health.count > 400 { health.removeFirst(health.count - 400) }
        }
    }

    public func samples(since date: Date) -> [ChargeSample] {
        samples.filter { $0.t >= date }
    }

    /// 从自己的记录里学 75% 以上的充电速度（% / 分钟）。少于 20 分钟的数据不算。
    public func learnedRate() -> Double? {
        var gained = 0.0
        var minutes = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) {
            let span = b.t.timeIntervalSince(a.t) / 60
            guard span > 0, span <= 30, a.c, b.c, a.x, b.x, a.p >= 75, b.p > a.p else { continue }
            gained += Double(b.p - a.p)
            minutes += span
        }
        guard minutes >= 20, gained > 0 else { return nil }
        return max(0.05, min(3, gained / minutes))
    }

    public static func load(from url: URL) -> ChargeHistory {
        guard let data = try? Data(contentsOf: url) else { return ChargeHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(ChargeHistory.self, from: data)) ?? ChargeHistory()
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
