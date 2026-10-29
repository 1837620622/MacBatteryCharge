import Foundation
import BatteryCore

/// CI 用的自检，不弹窗、不点按钮，直接走真实的更新路径：查最新版、下载安装包、核对校验码，
/// 再用 `sudo -n` 跑一次安装器（CI 的机器上没有人能输管理员密码框），最后核对装上的版本号。结果写进报告。
enum UpdateSelfTest {
    static func run(to report: URL) -> Bool {
        let box = ResultBox()
        let finished = DispatchSemaphore(value: 0)
        Task {
            box.value = await execute()
            finished.signal()
        }
        finished.wait()
        let (passed, lines) = box.value ?? (false, ["自检没有返回结果"])
        try? (lines.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
        return passed
    }

    private static func execute() async -> (Bool, [String]) {
        var lines: [String] = []
        do {
            let release = try await UpdateCheck.fetchLatest()
            lines.append("最新版本：\(release.version)")
            guard let asset = release.package(arm64: AppUpdater.isArm64) else {
                return (false, lines + ["没有适合这台机器的安装包"])
            }
            lines.append("安装包：\(asset.name)，\(asset.size) 字节，校验码 \(asset.sha256 ?? "无")")
            let file = try await AppUpdater.download(asset)
            lines.append("下载并核对校验码：通过")
            let install = Shell.run("/usr/bin/sudo", ["-n", "/usr/sbin/installer", "-pkg", file.path, "-target", "/"])
            lines.append("安装器退出码：\(install.status)")
            if install.status != 0 { lines.append("安装器输出：\(install.err)") }
            let installed = Installation.installedVersion()
            lines.append("装上后的版本：\(installed ?? "读不到")")
            let passed = install.status == 0 && installed == release.version
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
