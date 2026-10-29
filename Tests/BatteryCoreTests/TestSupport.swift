import XCTest
@testable import BatteryCore

/// 测试固定用中文断言。界面语言会跟系统走，CI 机器上是英文，
/// 所以断言具体句子前先把语言钉住，改语言相关的测试自己再切。
func pinChineseUI() {
    Lang.current = .zh
}
