import CryptoKit
import Foundation
import BatteryCore

/// 自动更新：把这一版的安装包下到临时文件夹，核对大小和 SHA-256、再核对签名，最后用系统的管理员密码框跑一次安装器。
/// 装完由 AppModel 退出并打开新版本。哪一步不行就写明原因，不把用户领去网页上自己下。
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

    /// 下载并核对。没有签名文件的版本不下；核对不过的文件马上删掉，不留给安装器。
    static func download(_ asset: ReleaseAsset, signature: ReleaseAsset?) async throws -> URL {
        guard let signature else {
            throw UpdateError(T("这个版本没有签名，不能自动安装。"))
        }
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
            let signatureText = try await fetchText(signature.url)
            try verifySignature(of: file, signature: signatureText)
        } catch {
            try? fm.removeItem(at: file)
            throw error
        }
        return file
    }

    /// 读一个很小的文本文件（签名文件）。
    private static func fetchText(_ url: URL) async throws -> String {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError(T("下载没有成功，请检查网络。"))
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// 大小和校验码都要对。GitHub 没给校验码的版本不自动装。
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

    /// 签名是发布流程用私钥签的；App 里只放公钥（Info.plist 的 MBCUpdatePublicKey）。
    /// 公钥不是秘密。只有拿着私钥的发布流程，才签得出能过这一关的安装包。
    static func verifySignature(of file: URL, signature text: String) throws {
        guard let keyText = Bundle.main.object(forInfoDictionaryKey: "MBCUpdatePublicKey") as? String,
              let keyData = Data(base64Encoded: keyText),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            throw UpdateError(T("应用里的公钥读不出来，不自动安装。"))
        }
        guard let signature = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              signature.count == 64 else {
            throw UpdateError(T("签名文件格式不对，没有安装。"))
        }
        guard key.isValidSignature(signature, for: try Data(contentsOf: file)) else {
            throw UpdateError(T("签名对不上，没有安装。"))
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
