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

/// 把异步的结果交回同步的等待。只给自检用。
private final class ResultBox: @unchecked Sendable {
    var value: (Bool, [String])?
}
