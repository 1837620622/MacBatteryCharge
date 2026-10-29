import Foundation

/// 换版本时留下、过后该删的东西。名字固定，在「应用程序」里一眼能认出来。
public enum UpdateResidue {
    /// 换版本时换下来的旧版本。留着是为了出问题时能退回去；新版本正常打开以后，下次启动就删。
    public static let previousName = ".MacBatteryCharge-previous.app"
    /// 拷贝到一半、或者没换上去的新版本。
    public static let incomingName = ".MacBatteryCharge-incoming.app"

    /// 要删的名字。没换上去的新版本一律删；备份只在运行的版本比它新（说明新版已经正常打开过）、
    /// 或者备份读不出版本号的时候删。
    public static func removable(in names: [String], runningVersion: String, backupVersion: String?) -> [String] {
        names.filter { name in
            switch name {
            case incomingName:
                return true
            case previousName:
                guard let backupVersion else { return true }
                return AppVersion.isNewer(runningVersion, than: backupVersion)
            default:
                return false
            }
        }
    }
}
