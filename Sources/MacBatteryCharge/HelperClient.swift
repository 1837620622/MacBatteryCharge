import Foundation
import BatteryCore

/// 和放电帮手说话。一问一答，每次连一下就断开，在后台队列里调用。
enum HelperClient {
    static func send(_ request: HelperRequest) -> HelperStatus? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let size = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: size) { chars in
                _ = HelperInfo.socketPath.withCString { strncpy(chars, $0, size - 1) }
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return nil }

        let line = HelperCoding.line(request)
        let sent = line.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            var sent = 0
            while sent < buffer.count {
                let written = write(fd, base + sent, buffer.count - sent)
                if written <= 0 { break }
                sent += written
            }
            return sent
        }
        guard sent == line.count else { return nil }

        var data = Data()
        var byte: UInt8 = 0
        while data.count < 8192, read(fd, &byte, 1) == 1, byte != 0x0A { data.append(byte) }
        return HelperStatus.decode(data)
    }

    static func status() -> HelperStatus? { send(HelperRequest(cmd: .status)) }
}

/// 在系统自己的密码框里装、卸放电帮手。
enum HelperInstaller {
    static var bundledBinary: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/MacBatteryChargeHelper")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: HelperInfo.launchDaemonPlist) }

    static func plist(version: String, uid: uid_t) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(HelperInfo.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(HelperInfo.installedBinary)</string>
                <string>--uid</string><string>\(uid)</string>
                <string>--app-version</string><string>\(version)</string>
            </array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><true/>
            <key>ProcessType</key><string>Background</string>
            <key>StandardOutPath</key><string>/var/log/\(HelperInfo.label).log</string>
            <key>StandardErrorPath</key><string>/var/log/\(HelperInfo.label).log</string>
        </dict>
        </plist>
        """
    }

    /// 装或更新。一次管理员密码。
    static func install(version: String) -> Shell.AdminResult {
        guard let binary = bundledBinary else { return .failed(T("这份软件里没有放电帮手。请用安装包或磁盘映像里的版本。")) }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("mbc-helper-\(UUID().uuidString).plist")
        do {
            try plist(version: version, uid: getuid()).write(to: temp, atomically: true, encoding: .utf8)
        } catch {
            return .failed(T("写不了临时文件：%@", ["\(error.localizedDescription)"]))
        }
        defer { try? FileManager.default.removeItem(at: temp) }
        let label = HelperInfo.label
        let script = [
            "set -e",
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "/bin/launchctl bootout system/\(label) 2>/dev/null || true",
            "/bin/cp \(Shell.quoted(binary.path)) \(Shell.quoted(HelperInfo.installedBinary))",
            "/usr/sbin/chown root:wheel \(Shell.quoted(HelperInfo.installedBinary))",
            "/bin/chmod 755 \(Shell.quoted(HelperInfo.installedBinary))",
            "/usr/bin/xattr -cr \(Shell.quoted(HelperInfo.installedBinary)) 2>/dev/null || true",
            "/bin/cp \(Shell.quoted(temp.path)) \(Shell.quoted(HelperInfo.launchDaemonPlist))",
            "/usr/sbin/chown root:wheel \(Shell.quoted(HelperInfo.launchDaemonPlist))",
            "/bin/chmod 644 \(Shell.quoted(HelperInfo.launchDaemonPlist))",
            "/bin/launchctl bootstrap system \(Shell.quoted(HelperInfo.launchDaemonPlist))",
        ].joined(separator: "; ")
        return Shell.runAsAdmin(script, prompt: T("充电上限要装一个放电帮手，这样白天接着电源也能把电放到上限。只装这一次。"))
    }

    /// 卸载：先让帮手把电源接回来，再删。
    static func uninstallScript() -> String {
        let label = HelperInfo.label
        return [
            "/bin/launchctl bootout system/\(label) 2>/dev/null || true",
            "/bin/rm -f \(Shell.quoted(HelperInfo.launchDaemonPlist)) \(Shell.quoted(HelperInfo.installedBinary)) \(Shell.quoted(HelperInfo.socketPath))",
        ].joined(separator: "; ")
    }

    /// 卸载前先把电源接回来。这一步必须确认成功：
    /// 帮手如果被 SIGKILL，SMC 里「适配器断开」是持久状态，删掉帮手后就没人能把它接回去了，
    /// 用户会一直以为没插电（直到下次装帮手或重启）。宁可让用户重启后再卸，也不留下这个状态。
    static func uninstall(adapterMayBeCut: Bool) -> Shell.AdminResult {
        let status = HelperClient.send(HelperRequest(cmd: .reset))
        if status?.adapterEnabled == false {
            return .failed(T("帮手没有把电源接回来。请重启这台 Mac 之后再卸载。"))
        }
        // 帮手没有响应，但上次看到电源是断开的：现在是什么状态不知道，就不删。
        if status == nil, adapterMayBeCut {
            return .failed(T("帮手现在没有响应，而上次看到电源是断开的。请重启这台 Mac 之后再卸载。"))
        }
        return Shell.runAsAdmin(uninstallScript(), prompt: T("充电上限要卸载放电帮手，并把电源接回来。"))
    }
}
