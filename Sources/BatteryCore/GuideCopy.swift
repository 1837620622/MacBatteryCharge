import Foundation

/// 第一次打开的三步引导。每步一句标题、两行以内的正文。
///
/// 都是计算属性：切换语言后立刻跟着变，不需要重启。
public enum GuideCopy {
    public static var intro: String { T("三步就能用上。读电池不需要任何授权。") }

    public static var titles: [String] {
        [
            T("先选一个模式"),
            T("它会记住你的习惯"),
            T("点一下就能看到它"),
        ]
    }

    public static var bodies: [String] {
        [
            T("新装默认是智能：平时停在 80%，不一直满电。固定时间段和一直充满也在上面。"),
            T("每天第一次长时间接着电源后拔掉，就记作一次。记满 3 次，就在你平时拔电源前把电补好。"),
            T("点菜单栏的图标打开窗口。点刘海展开，再点一下收回去；插拔电源时它会自己弹出来。"),
        ]
    }
}
