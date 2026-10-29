import CryptoKit
import Foundation
import BatteryCore

/// 自动更新：把这一版的安装包下到临时文件夹，核对大小和 SHA-256，再用系统的管理员密码框跑一次安装器。
/// 装完由 AppModel 退出并打开新版本。哪一步不行就给出原因，界面上配一个“去下载页面”的跳转。
enum AppUpdater {
    enum Outcome: Equatable {
        case installed
        case cancelled
        case failed(String)
    }

    /// 本程序是哪种芯片编的，就要哪种安装包。
    static let isArm64: Bool = {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }()

    private static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MacBatteryChargeUpdate", isDirectory: true)
    }

    /// 下载并核对。核对不过的文件马上删掉，不留给安装器。
    static func download(_ asset: ReleaseAsset) async throws -> URL {
        let fm = FileManager.default
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let request = URLRequest(url: asset.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 300)
        let temporary: URL
        do {
            let (url, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError(T("下载没有成功，请检查网络。"))
            }
            temporary = url
        } catch let error as UpdateError {
            throw error
        } catch {
            throw UpdateError(T("下载没有成功：%@", ["\(error.localizedDescription)"]))
        }
        let file = folder.appendingPathComponent(asset.name)
        try fm.moveItem(at: temporary, to: file)
        do {
            try verify(file, against: asset)
        } catch {
            try? fm.removeItem(at: file)
            throw error
        }
        return file
    }

    /// 大小和校验码都要对。GitHub 没给校验码的版本不自动装，只给下载页面。
    static func verify(_ file: URL, against asset: ReleaseAsset) throws {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
        if asset.size > 0, size != asset.size {
            throw UpdateError(T("下载的文件大小不对，没有安装。"))
        }
        guard let expected = asset.sha256 else {
            throw UpdateError(T("这个版本没有校验码，不能自动安装。"))
        }
        let actual = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw UpdateError(T("下载的文件校验不对，没有安装。"))
        }
    }

    /// 用系统的管理员密码框跑一次安装器。装完核对版本号，对得上才算装好。
    static func install(_ file: URL, version: String) -> Outcome {
        let script = "/usr/sbin/installer -pkg \(Shell.quoted(file.path)) -target /"
        switch Shell.runAsAdmin(script, prompt: T("充电上限要更新到 %@，请输入一次管理员密码。", ["\(version)"])) {
        case .cancelled:
            return .cancelled
        case .failed(let text):
            return .failed(T("安装没有成功：%@", ["\(text)"]))
        case .ok:
            guard Installation.installedVersion() == version else {
                return .failed(T("装完了，但版本号对不上。"))
            }
            try? FileManager.default.removeItem(at: file)
            return .installed
        }
    }
}
