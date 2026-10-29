// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacBatteryCharge",
    platforms: [.macOS(.v14)],
    targets: [
        // 纯逻辑：时间表、读数换算、建议、更新版本号。只依赖 Foundation，方便在测试里跑。
        .target(name: "BatteryCore"),
        // 系统充电上限走私有的 PowerUI，用运行时调用，不把私有框架链进二进制。
        .target(
            name: "PowerBridge",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("Foundation")]
        ),
        .executableTarget(
            name: "MacBatteryCharge",
            dependencies: ["BatteryCore", "PowerBridge"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("CryptoKit"),
            ]
        ),
        .testTarget(name: "BatteryCoreTests", dependencies: ["BatteryCore"]),
    ]
)
