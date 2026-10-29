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
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
