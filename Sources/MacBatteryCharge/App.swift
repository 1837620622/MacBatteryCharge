import AppKit

@main
enum Main {
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
            exit(UpdateSelfTest.run(to: URL(fileURLWithPath: path)) ? 0 : 1)
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
