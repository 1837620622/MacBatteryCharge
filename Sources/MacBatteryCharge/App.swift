import AppKit

@main
enum Main {
    /// 命令行里 `--flag 值` 的值。
    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot") {
            let path = index + 1 < arguments.count ? arguments[index + 1] : "snapshots"
            exit(Snapshot.run(to: URL(fileURLWithPath: path)) ? 0 : 1)
        }
        if arguments.contains("--bench") {
            exit(Benchmark.run() ? 0 : 1)
        }
        if arguments.contains("--bench-live") {
            exit(Benchmark.live() ? 0 : 1)
        }
        if let index = arguments.firstIndex(of: "--selftest-update") {
            let path = index + 1 < arguments.count ? arguments[index + 1] : "selftest-update.txt"
            let pkg = value(after: "--pkg", in: arguments).map { URL(fileURLWithPath: $0) }
            exit(UpdateSelfTest.run(to: URL(fileURLWithPath: path), pkg: pkg, expect: value(after: "--expect", in: arguments)) ? 0 : 1)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        if let index = arguments.firstIndex(of: "--selftest-menubar") {
            delegate.selfTestReport = URL(fileURLWithPath: index + 1 < arguments.count ? arguments[index + 1] : "selftest-menubar.txt")
        }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
