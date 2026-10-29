import Foundation
import CryptoKit
import BatteryCore

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case downloading(ReleaseInfo, Double)
    /// 安装器已经打开，等它把新版本放进“应用程序”。
    case installing(ReleaseInfo)
    case failed(String)
}

enum UpdateCheck {
    static let latestURL = URL(string: "https://api.github.com/repos/1837620622/MacBatteryCharge/releases/latest")!

    static func fetchLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("MacBatteryCharge/\(Installation.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError("GitHub 没有返回版本信息")
        }
        guard let release = ReleaseInfo.parse(data) else { throw UpdateError("版本信息看不懂") }
        return release
    }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("com.macbatterycharge.app", isDirectory: true)
    }

    static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct UpdateError: LocalizedError {
    var text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}

/// 下载 PKG 并报告进度。回调在 URLSession 的后台队列上。
final class PackageDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private let onFinish: @Sendable (Result<URL, Error>) -> Void
    private let lock = NSLock()
    private var finished = false

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void, onFinish: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    func start(_ url: URL) {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.setValue("MacBatteryCharge/\(Installation.version)", forHTTPHeaderField: "User-Agent")
        session.downloadTask(with: request).resume()
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let first = !finished
        finished = true
        lock.unlock()
        if first { onFinish(result) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            return finish(.failure(UpdateError("下载失败（\(http.statusCode)）")))
        }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        session.finishTasksAndInvalidate()
    }
}
