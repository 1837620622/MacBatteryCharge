import AppKit
import Foundation
import BatteryCore

/// 本机日志。只写这台 Mac 上的文本文件，不联网、不上传。
///
/// 目的只有一个：出问题时能带上现场去提 issue。
/// 所以只记「发生了什么」，不记屏幕内容、不记窗口标题，路径里的用户名也换成 `~`。
public enum Log {
    /// 超过这个大小就换一份旧的，免得一个文件长到几十兆。
    static let maxBytes = 512 * 1024
    static let keepFiles = 2

    private static let lock = NSLock()

    static var directory: URL { AppSettings.directory.appendingPathComponent("Logs", isDirectory: true) }
    static var currentURL: URL { directory.appendingPathComponent("app.log") }
    /// 正在运行标记。正常退出时删掉；启动时发现它还在，说明上次没有走到退出流程。
    static var runningURL: URL { directory.appendingPathComponent("running") }

    static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    public static func write(_ level: String, _ text: String, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(stamp.string(from: date)) [\(level)] \(redact(text))\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: currentURL.path)[.size]) as? Int, size > maxBytes {
            rotate()
        }
        if let handle = try? FileHandle(forWritingTo: currentURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: currentURL)
        }
        // 日志里有调用栈和版本，别让同一台机器上的其他用户读到。
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: currentURL.path)
    }

    private static func rotate() {
        let fm = FileManager.default
        try? fm.removeItem(at: directory.appendingPathComponent("app.\(keepFiles).log"))
        for index in stride(from: keepFiles - 1, through: 1, by: -1) {
            let from = directory.appendingPathComponent("app.\(index).log")
            let to = directory.appendingPathComponent("app.\(index + 1).log")
            if fm.fileExists(atPath: from.path) { try? fm.moveItem(at: from, to: to) }
        }
        if fm.fileExists(atPath: currentURL.path) {
            try? fm.moveItem(at: currentURL, to: directory.appendingPathComponent("app.1.log"))
        }
    }

    /// 把用户名之类的路径换掉，日志里不留个人信息。
    static func redact(_ text: String) -> String {
        var value = text
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if !home.isEmpty { value = value.replacingOccurrences(of: home, with: "~") }
        return value
    }

    /// 启动时调用。上次没正常退出就在日志里留一条。
    public static func beginSession() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: runningURL.path) {
            write("crash", T("上次没有正常退出（没有走到退出流程）"))
        }
        try? Data().write(to: runningURL)
        write("launch", T("启动 %@ · macOS %@", ["\(Installation.version)", "\(ProcessInfo.processInfo.operatingSystemVersionString)"]))
    }

    /// 正常退出时调用。
    public static func endSession() {
        write("quit", T("正常退出"))
        try? FileManager.default.removeItem(at: runningURL)
    }

    /// 最近这么多行，给 issue 用。旧的在前。
    public static func recentLines(_ count: Int = 120) -> [String] {
        guard let text = try? String(contentsOf: currentURL, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.suffix(count))
    }

    /// 装上崩溃处理。AppKit 的异常在进程结束前会走到这里，写一行再让系统按原样处理。
    public static func installCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let name = exception.name.rawValue
            let reason = exception.reason ?? ""
            let stack = exception.callStackSymbols.prefix(24).joined(separator: " | ")
            write("crash", "\(name): \(reason) @ \(stack)")
        }
    }

    /// 打开日志所在的文件夹。找不到就先建一个，不要让访达弹错误。
    static func openLogFolder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([currentURL])
    }
}
