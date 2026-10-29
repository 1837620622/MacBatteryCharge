import Foundation

/// 三段版本号，可以带 v 前缀，少写的段按 0。
public struct AppVersion: Comparable, Sendable {
    public var parts: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(piece) else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }
        parts = numbers
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = AppVersion(candidate), let b = AppVersion(current) else { return false }
        return b < a
    }
}

public struct ReleaseAsset: Equatable, Sendable {
    public var name: String
    public var url: URL
    public var size: Int
    /// GitHub 给的 "sha256:..." 去掉前缀后的十六进制。
    public var sha256: String?
}

public struct ReleaseInfo: Equatable, Sendable {
    public var tag: String
    public var version: String
    public var page: URL?
    public var notes: String
    public var assets: [ReleaseAsset]

    /// 解析 GitHub releases/latest 的 JSON。
    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        var version = tag
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }
        let assets: [ReleaseAsset] = (json["assets"] as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String,
                  let link = item["browser_download_url"] as? String,
                  let url = URL(string: link) else { return nil }
            var digest = item["digest"] as? String
            if let value = digest, value.hasPrefix("sha256:") {
                digest = String(value.dropFirst("sha256:".count)).lowercased()
            } else {
                digest = nil
            }
            return ReleaseAsset(name: name, url: url, size: Reading.integer(item["size"]) ?? 0, sha256: digest)
        }
        return ReleaseInfo(tag: tag, version: version,
                           page: (json["html_url"] as? String).flatMap(URL.init(string:)),
                           notes: (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                           assets: assets)
    }

    /// Apple 芯片拿 arm64 的 PKG，Intel 拿 intel 的 PKG。
    public func package(arm64: Bool) -> ReleaseAsset? {
        let key = arm64 ? "arm64" : "intel"
        return assets.first { $0.name.lowercased().hasSuffix(".pkg") && $0.name.lowercased().contains(key) }
    }
}
