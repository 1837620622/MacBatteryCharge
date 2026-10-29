import Foundation
import BatteryCore

/// CI 用的自检，不弹窗、不点按钮，走真实的更新路径，结果写进报告。
/// 默认：查最新版、下载、核对校验码和签名，再用 `sudo -n` 跑安装器，核对装上的版本号。
/// `--pkg 安装包 --expect 版本`：直接用这份刚打好的安装包（不联网），核对它的签名、安装、版本号。
enum UpdateSelfTest {
    static func run(to report: URL, pkg: URL?, expect: String?) -> Bool {
        let box = ResultBox()
        let finished = DispatchSemaphore(value: 0)
        Task {
            box.value = await execute(pkg: pkg, expect: expect)
            finished.signal()
        }
        finished.wait()
        let (passed, lines) = box.value ?? (false, ["自检没有返回结果"])
        try? (lines.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
        return passed
    }

    private static func execute(pkg: URL?, expect: String?) async -> (Bool, [String]) {
        var lines: [String] = []
        do {
            let file: URL
            let version: String
            if let pkg {
                guard let expect else { return (false, ["--pkg 要和 --expect 版本号一起用"]) }
                let text = try String(contentsOf: URL(fileURLWithPath: pkg.path + ".sig"), encoding: .utf8)
                try AppUpdater.verifySignature(of: pkg, signature: text)
                lines.append("签名核对：通过（\(pkg.lastPathComponent)）")
                file = pkg
                version = expect
            } else {
                let release = try await UpdateCheck.fetchLatest()
                lines.append("最新版本：\(release.version)")
                guard let asset = release.package(arm64: AppUpdater.isArm64) else {
                    return (false, lines + ["没有适合这台机器的安装包"])
                }
                let signature = release.assets.first { $0.name == asset.name + ".sig" }
                lines.append("安装包：\(asset.name)，\(asset.size) 字节，校验码 \(asset.sha256 ?? "无")，签名文件\(signature == nil ? "没有" : "有")")
                file = try await AppUpdater.download(asset, signature: signature)
                lines.append("下载并核对校验码和签名：通过")
                version = release.version
            }
            let install = Shell.run("/usr/bin/sudo", ["-n", "/usr/sbin/installer", "-pkg", file.path, "-target", "/"])
            lines.append("安装器退出码：\(install.status)")
            if install.status != 0 { lines.append("安装器输出：\(install.err)") }
            let installed = Installation.installedVersion()
            lines.append("装上后的版本：\(installed ?? "读不到")，应该是 \(version)")
            let passed = install.status == 0 && installed == version
            lines.append(passed ? "结果：通过" : "结果：失败")
            return (passed, lines)
        } catch {
            lines.append("出错：\(error.localizedDescription)")
            lines.append("结果：失败")
            return (false, lines)
        }
    }
}

/// `--selftest-inplace 报告 --pkg 安装包 --expect 版本`：在一个临时文件夹里模拟「应用程序」，
/// 把正在跑的这份当成旧版，用这份安装包原地换一次，核对解包、身份、签名、换上以后的版本和备份。不碰真正的「应用程序」。
enum InPlaceSelfTest {
    static func run(to report: URL, pkg: URL?, expect: String?) -> Bool {
        var lines: [String] = []
        let passed = execute(pkg: pkg, expect: expect, lines: &lines)
        lines.append(passed ? "结果：通过" : "结果：失败")
        try? (lines.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
        return passed
    }

    private static func execute(pkg: URL?, expect: String?, lines: inout [String]) -> Bool {
        guard let pkg, let expect else {
            lines.append("需要 --pkg 和 --expect")
            return false
        }
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory.appendingPathComponent("mbc-inplace-\(UUID().uuidString)", isDirectory: true)
        let folder = sandbox.appendingPathComponent("Applications", isDirectory: true)
        let installed = folder.appendingPathComponent("MacBatteryCharge.app", isDirectory: true)
        defer { try? fm.removeItem(at: sandbox) }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            guard Shell.run("/usr/bin/ditto", [Bundle.main.bundleURL.path, installed.path]).status == 0 else {
                lines.append("准备旧版本：失败")
                return false
            }
            lines.append("旧版本：\(Installation.installedVersion(at: installed) ?? "读不到")")
            let app = try AppUpdater.unpack(pkg, version: expect)
            lines.append("解包并核对身份、签名：通过（\(expect)）")
            let outcome = AppUpdater.replaceInPlace(with: app, destination: installed)
            guard outcome == .installed else {
                lines.append("原地换：没有成功（\(outcome)）")
                return false
            }
            lines.append("原地换：通过")
            let now = Installation.installedVersion(at: installed)
            lines.append("换上以后的版本：\(now ?? "读不到")，应该是 \(expect)")
            let backup = folder.appendingPathComponent(UpdateResidue.previousName)
            lines.append("备份还在：\(fm.fileExists(atPath: backup.path) ? "是" : "否")")
            let leftover = folder.appendingPathComponent(UpdateResidue.incomingName)
            lines.append("没有残留的新副本：\(fm.fileExists(atPath: leftover.path) ? "否，有残留" : "是")")
            let verified = Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", installed.path]).status == 0
            lines.append("换上以后签名完整：\(verified ? "是" : "否")")
            return now == expect && fm.fileExists(atPath: backup.path)
                && !fm.fileExists(atPath: leftover.path) && verified
        } catch {
            lines.append("出错：\(error.localizedDescription)")
            return false
        }
    }
}

/// 把异步的结果交回同步的等待。只给自检用。
private final class ResultBox: @unchecked Sendable {
    var value: (Bool, [String])?
}
