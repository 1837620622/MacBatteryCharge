import Foundation

/// 等新版本装完再重新打开。纯逻辑，方便测试。
///
/// 程序每隔几秒看一眼「应用程序」里装的那份，`observe` 传进去的是它的指纹（版本加上程序文件的大小和修改时间），
/// 没有更新的版本可换时传 nil。拷贝还没完的时候，指纹一直在变；连续两次看到同一份，才说明装完了，返回 true。
public struct InstallWatch: Equatable, Sendable {
    /// 上一次看到的指纹。
    private var last: String?

    public init() {}

    /// 看一眼。返回 true 表示装完了，该重新打开了。
    public mutating func observe(_ fingerprint: String?) -> Bool {
        guard let fingerprint else {
            last = nil
            return false
        }
        guard last == fingerprint else {
            last = fingerprint
            return false
        }
        return true
    }
}
