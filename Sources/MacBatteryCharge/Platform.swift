import AppKit
import ServiceManagement
import UserNotifications
import BatteryCore

/// 登录时打开：用系统的「登录项」，系统设置里能看到也能关。
enum LoginItem {
    static let legacyAgentLabel = "com.macbatterycharge.agent"

    static var legacyAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(legacyAgentLabel).plist")
    }

    enum State: Equatable {
        case on
        case off
        case needsApproval
        case needsApplications
    }

    static var state: State {
        if !Installation.isInApplications { return .needsApplications }
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    /// 按开关登记或取消。返回给用户看的一句话；没问题时返回 nil。
    @discardableResult
    static func sync(enabled: Bool) -> String? {
        guard Installation.isInApplications else {
            return enabled ? "放进“应用程序”后，登录时才会自己打开。" : nil
        }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            if enabled && service.status == .requiresApproval { return "要在系统设置的“登录项”里允许。" }
            return "登录项没有改好：\(error.localizedDescription)"
        }
        if enabled && service.status == .requiresApproval { return "要在系统设置的“登录项”里允许。" }
        return nil
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// 2.x 用的是 LaunchAgent。换成登录项后把它删掉。
    /// 这次正是被它带起来的（有 --background）时不 bootout，否则会把自己一起结束；删掉文件后下次登录就不会再跑。
    static func removeLegacyAgent(launchedByAgent: Bool) {
        let url = legacyAgentURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if !launchedByAgent {
            Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(legacyAgentLabel)"])
        }
        try? FileManager.default.removeItem(at: url)
    }
}

/// 只有用户打开「通知」后才申请权限。
enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static func requestAuthorization(_ done: @escaping @Sendable (Bool) -> Void) {
        guard available else { return done(false) }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            done(granted)
        }
    }

    static func post(id: String, title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// 安装位置、搬进“应用程序”、卸载。
enum Installation {
    static let applicationsURL = URL(fileURLWithPath: "/Applications/MacBatteryCharge.app")

    static var bundleURL: URL { Bundle.main.bundleURL }

    static var isBundle: Bool { bundleURL.pathExtension == "app" }

    static var isInApplications: Bool {
        isBundle && bundleURL.standardizedFileURL.path.hasPrefix("/Applications/")
    }

    /// 从磁盘映像或下载目录直接打开时，提示搬进“应用程序”。
    static var shouldOfferMove: Bool { isBundle && !isInApplications }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// 读磁盘上的 Info.plist，不走 Bundle 的缓存。
    static func installedVersion(at url: URL = applicationsURL) -> String? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let dictionary = NSDictionary(contentsOf: plist) else { return nil }
        return dictionary["CFBundleShortVersionString"] as? String
    }

    /// 复制到 /Applications，去掉隔离标记。没有写权限时请系统要一次管理员密码。
    static func copyToApplications() -> Result<URL, InstallError> {
        let fm = FileManager.default
        let source = bundleURL
        let target = applicationsURL
        do {
            if fm.fileExists(atPath: target.path) { try fm.trashItem(at: target, resultingItemURL: nil) }
            try fm.copyItem(at: source, to: target)
        } catch {
            let script = "/bin/rm -rf \(Shell.quoted(target.path)); /usr/bin/ditto \(Shell.quoted(source.path)) \(Shell.quoted(target.path))"
            switch Shell.runAsAdmin(script, prompt: "充电上限要放进“应用程序”。") {
            case .ok: break
            case .cancelled: return .failure(.cancelled)
            case .failed(let text): return .failure(.failed(text))
            }
        }
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])
        return .success(target)
    }

    enum InstallError: Error, Equatable {
        case cancelled
        case failed(String)

        var message: String {
            switch self {
            case .cancelled: return "已取消"
            case .failed(let text): return text
            }
        }
    }

    /// 等这个进程退出后再打开另一份，避免同一个 bundle id 只激活旧进程。
    @MainActor
    static func relaunch(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", url.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// 关掉登录项，删掉配置，把程序移到废纸篓。充电上限和低电量保持现在的值。
    static func uninstall() -> Result<Void, InstallError> {
        try? SMAppService.mainApp.unregister()
        LoginItem.removeLegacyAgent(launchedByAgent: false)
        try? FileManager.default.removeItem(at: AppSettings.directory)
        var targets = [bundleURL]
        if bundleURL.standardizedFileURL != applicationsURL, FileManager.default.fileExists(atPath: applicationsURL.path) {
            targets.append(applicationsURL)
        }
        for target in targets where isBundleSafeToDelete(target) {
            do {
                try FileManager.default.trashItem(at: target, resultingItemURL: nil)
            } catch {
                let script = "/bin/rm -rf \(Shell.quoted(target.path)); /usr/sbin/pkgutil --forget com.macbatterycharge.pkg >/dev/null 2>&1; true"
                switch Shell.runAsAdmin(script, prompt: "充电上限要从“应用程序”里删掉自己。") {
                case .ok: continue
                case .cancelled: return .failure(.cancelled)
                case .failed(let text): return .failure(.failed(text))
                }
            }
        }
        return .success(())
    }

    private static func isBundleSafeToDelete(_ url: URL) -> Bool {
        url.pathExtension == "app" && url.lastPathComponent.hasPrefix("MacBatteryCharge") && !url.path.contains("/AppTranslocation/")
    }
}
