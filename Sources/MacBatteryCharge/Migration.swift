import Foundation
import BatteryCore

/// 每次启动都跑一遍：把上一版留下的东西收拾掉。能自己修的自己修，不用重启电脑，也不用管理员密码。
enum Migration {
    /// 返回几句要写进日志的话；没有要清的就是空的。
    static func run() -> [String] {
        let fm = FileManager.default
        var notes: [String] = []
        let folder = Installation.applicationsURL.deletingLastPathComponent()
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        let previous = folder.appendingPathComponent(UpdateResidue.previousName)
        let removable = UpdateResidue.removable(in: names, runningVersion: Installation.version,
                                                backupVersion: Installation.installedVersion(at: previous))
        for name in removable {
            if (try? fm.removeItem(at: folder.appendingPathComponent(name))) != nil {
                notes.append("清掉了换版本时留下的 \(name)")
            }
        }
        // 下载用的临时文件夹。刚启动时没有在下载，删掉，下次下载会重新建。
        let temporary = fm.temporaryDirectory.appendingPathComponent("MacBatteryChargeUpdate", isDirectory: true)
        if fm.fileExists(atPath: temporary.path), (try? fm.removeItem(at: temporary)) != nil {
            notes.append("清掉了旧的更新临时文件")
        }
        return notes
    }
}
