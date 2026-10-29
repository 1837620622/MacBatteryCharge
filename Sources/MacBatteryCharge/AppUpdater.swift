import CryptoKit
import Foundation
import BatteryCore

/// 自动更新：下载安装包 → 核对大小和 SHA-256 → 核对签名 → 解开安装包，取出新的 App，核对是同一个 App、同一版
/// → 在「应用程序」里原地换掉旧的（旧的留作备份，新版本正常打开以后，下次启动再删）。
/// 「应用程序」允许当前用户写入时不需要密码（装的人通常是管理员）。不允许写入时，只有用户点了按钮，才弹一次管理员密码框跑系统安装器。
enum AppUpdater {
    enum Outcome: Equatable {
        case installed
        /// 「应用程序」不让当前用户直接换，要管理员密码。只有用户点了按钮才会去要。
        case needsPassword
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

    /// 下载并核对。没有签名文件的版本不下；核对不过的文件马上删掉，不留给安装。
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

    /// 自动安装：解开、换上。不要密码；只有「应用程序」不让写入时，才返回 needsPassword。
    static func install(_ package: URL, version: String) -> Outcome {
        guard Installation.isInApplications else {
            return .failed(T("要放进“应用程序”里，才能自动更新。"))
        }
        do {
            let app = try unpack(package, version: version)
            let outcome = replaceInPlace(with: app)
            if outcome == .installed { cleanUp(package) }
            return outcome
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 用户点了按钮：弹一次管理员密码框，跑系统安装器，装完核对版本号。
    static func installWithPassword(_ package: URL, version: String) -> Outcome {
        let script = "/usr/sbin/installer -pkg \(Shell.quoted(package.path)) -target /"
        switch Shell.runAsAdmin(script, prompt: T("充电上限要更新到 %@，请输入一次管理员密码。", ["\(version)"])) {
        case .cancelled:
            return .needsPassword
        case .failed(let text):
            return .failed(T("安装没有成功：%@", ["\(text)"]))
        case .ok:
            guard Installation.installedVersion() == version else {
                return .failed(T("装完了，但版本号对不上。"))
            }
            cleanUp(package)
            return .installed
        }
    }

    /// 解开安装包，取出里面的 App。只用当前用户的权限，不要密码。
    static func unpack(_ package: URL, version: String) throws -> URL {
        let directory = folder.appendingPathComponent("unpacked", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        let result = Shell.run("/usr/sbin/pkgutil", ["--expand-full", package.path, directory.path])
        guard result.status == 0 else {
            throw UpdateError(T("安装包解不开：%@", ["\(result.err)"]))
        }
        guard let app = findApp(in: directory) else {
            throw UpdateError(T("安装包里没有找到 App。"))
        }
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info?["CFBundleShortVersionString"] as? String == version else {
            throw UpdateError(T("安装包里的 App 不是这一版，没有安装。"))
        }
        guard Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]).status == 0 else {
            throw UpdateError(T("安装包里的 App 签名不完整，没有安装。"))
        }
        return app
    }

    private static func findApp(in directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent == "MacBatteryCharge.app" { return item }
        }
        return nil
    }

    /// 在「应用程序」里原地换掉。新的先拷到旁边（同一个文件夹，同一块盘），再一步换过去；旧的留成备份。
    /// 文件夹可写、旧的 App 也是当前用户的才直接换：旧的要是 root 的（管理员装的），备份就删不掉，留下残留。
    /// 这种情况走一次管理员密码的安装器，装完 App 归当前用户（安装包的收尾脚本会改），以后就不用密码了。
    static func replaceInPlace(with newApp: URL, destination: URL = Installation.applicationsURL) -> Outcome {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        let owner = (try? fm.attributesOfItem(atPath: destination.path)[.ownerAccountID] as? NSNumber)?.uint32Value
        guard fm.isWritableFile(atPath: parent.path), owner == getuid() else { return .needsPassword }
        let incoming = parent.appendingPathComponent(UpdateResidue.incomingName)
        try? fm.removeItem(at: incoming)
        let copied = Shell.run("/usr/bin/ditto", [newApp.path, incoming.path])
        guard copied.status == 0 else {
            try? fm.removeItem(at: incoming)
            return .failed(T("复制新版本没有成功：%@", ["\(copied.err)"]))
        }
        try? fm.removeItem(at: parent.appendingPathComponent(UpdateResidue.previousName))
        do {
            _ = try fm.replaceItemAt(destination, withItemAt: incoming, backupItemName: UpdateResidue.previousName)
        } catch {
            try? fm.removeItem(at: incoming)
            return .failed(T("换新版本没有成功：%@", ["\(error.localizedDescription)"]))
        }
        return .installed
    }

    private static func cleanUp(_ package: URL) {
        try? FileManager.default.removeItem(at: package)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("unpacked", isDirectory: true))
    }
}
