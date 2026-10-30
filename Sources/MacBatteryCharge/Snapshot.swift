import AppKit
import SwiftUI
import BatteryCore

/// `--snapshot 目录`：用假数据把三种模式的主窗口、设置、引导、刘海灵动岛和菜单栏图标画成 PNG。
/// 给 CI 看界面，也给 README 和宣传片用。不读也不改这台 Mac 上的任何设置。
enum Snapshot {
    @MainActor
    static func run(to directory: URL) -> Bool {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print(T("建不了目录：%@", ["\(error.localizedDescription)"]))
            return false
        }

        var ok = true
        func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

        // 中文和英文各一套，README 里中文用中文截图，英文用英文截图。
        for language in [AppLanguage.zh, AppLanguage.en] {
            let tag = language == .zh ? "zh" : "en"
            for mode in ChargeMode.allCases {
                let model = sampleModel(mode: mode, language: language)
                ok = render(RootView(model: model), size: RootView.popoverSize, appearance: .aqua,
                            to: file("main-\(mode.rawValue)-\(tag).png")) && ok
            }
            let model = sampleModel(mode: .smart, language: language)
            ok = render(RootView(model: model), size: RootView.popoverSize, appearance: .darkAqua,
                        to: file("main-smart-dark-\(tag).png")) && ok
            if let release = ReleaseInfo.parse(Data(#"{"tag_name":"v9.0.0","assets":[]}"#.utf8)) {
                let ready = sampleModel(mode: .smart, language: language)
                ready.loadPreviewUpdate(.available(release))
                ok = render(RootView(model: ready), size: RootView.popoverSize, appearance: .aqua,
                            to: file("main-update-ready-\(tag).png")) && ok
                let failed = sampleModel(mode: .smart, language: language)
                failed.loadPreviewUpdate(.failed(T("下载没有成功，请检查网络。")))
                ok = render(RootView(model: failed), size: RootView.popoverSize, appearance: .aqua,
                            to: file("main-update-failed-\(tag).png")) && ok
            }
            let settingsPage = sampleModel(mode: .smart, language: language)
            ok = render(RootView(model: settingsPage, page: .settings), size: RootView.popoverSize, appearance: .aqua,
                        to: file("settings-\(tag).png")) && ok
            let guidePage = sampleModel(mode: .smart, language: language)
            guidePage.showGuide = true
            ok = render(RootView(model: guidePage), size: RootView.popoverSize, appearance: .aqua,
                        to: file("guide-\(tag).png")) && ok
            ok = render(islandPreview(model: model, expanded: true), size: NSSize(width: 400, height: 190), appearance: .darkAqua,
                        to: file("island-expanded-\(tag).png")) && ok
            ok = render(islandPreview(model: model, expanded: false), size: NSSize(width: 400, height: 190), appearance: .darkAqua,
                        to: file("island-ears-\(tag).png")) && ok
        }
        ok = writeMenuBar(to: file("menubar.png")) && ok
        return ok
    }

    /// 假数据：80% 接着电源，有半年的记录，学到的拔电时间是 18:40 前后。
    @MainActor
    static func sampleModel(mode: ChargeMode, language: AppLanguage = .en) -> AppModel {
        let model = AppModel(preview: true, previewMode: mode, previewLanguage: language)
        let now = Calendar.current.date(bySettingHour: 14, minute: 10, second: 0, of: Date()) ?? Date()

        var battery = BatterySnapshot()
        battery.present = true
        battery.percent = 80
        battery.milliamps = 0
        battery.millivolts = 12_950
        battery.cycles = 212
        battery.designCycles = 1000
        battery.designCapacity = 6075
        battery.nominalCapacity = 5560
        battery.rawMaxCapacity = 5490
        battery.temperatureRaw = 3060
        battery.externalConnected = true
        battery.adapterWatts = 70

        let gib: UInt64 = 1 << 30
        let page: UInt64 = 16_384
        let memory = MemorySnapshot(totalBytes: 16 * gib, pageSize: page, free: 2 * gib / page, active: 6 * gib / page,
                                    inactive: 3 * gib / page, wired: 2 * gib / page, compressed: gib / page,
                                    speculative: 0, pressure: 1)
        let helper = HelperStatus(version: Installation.version, adapterControl: true, chargeControl: .system,
                                  adapterEnabled: true, percent: 80, external: true, leaseRemaining: 0)
        let reading = SystemReading(battery: battery, memory: memory, chargeLimit: .current(80),
                                    thermal: .nominal, date: now, helper: helper)
        model.loadPreview(reading, history: sampleHistory(ending: now), minute: currentMinute(now))
        return model
    }

    /// 最近 16 小时：白天接电源，18:00 到 21:00 用电池，电量在 60% 到 80% 之间。
    static func sampleHistory(ending end: Date) -> ChargeHistory {
        var history = ChargeHistory()
        var time = end.addingTimeInterval(-16 * 3600)
        while time <= end {
            let hour = Calendar.current.component(.hour, from: time)
            let plugged = !(hour >= 18 && hour < 21)
            let percent = plugged ? 80 : 60 + (hour % 5) * 3
            history.add(ChargeSample(t: time, p: percent, c: false, x: plugged, l: 80))
            time = time.addingTimeInterval(600)
        }
        return history
    }

    /// 灵动岛放在深灰底上，看得出它和屏幕的边。
    @MainActor
    static func islandPreview(model: AppModel, expanded: Bool) -> some View {
        let state = IslandState()
        state.geometry = NotchGeometry(screenFrame: NSRect(x: 0, y: 0, width: 400, height: 190), width: 190, height: 32, real: true)
        state.expanded = expanded
        state.ears = !expanded
        return ZStack(alignment: .top) {
            Color(white: 0.22)
            IslandView(model: model, state: state, onOpen: {})
        }
    }

    @MainActor
    static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL) -> Bool {
        let look = NSAppearance(named: appearance)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
        hosting.sizingOptions = []
        hosting.appearance = look
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = look
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        hosting.display()

        if let data = cachedPNG(of: hosting, size: size, appearance: look) {
            return write(data, to: url)
        }
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            print(T("画不出 %@", ["\(url.lastPathComponent)"]))
            return false
        }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return write(data, to: url)
    }

    @MainActor
    private static func cachedPNG(of view: NSView, size: NSSize, appearance: NSAppearance?) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        // 先铺窗口底色，SwiftUI 没画到的地方不会是透明的。
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// 菜单栏图标：上面一行是上限，下面一行是状态。
    @MainActor
    static func writeMenuBar(to url: URL) -> Bool {
        let image = MenuBarIcon.image(percent: 80, charging: true)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return false }
        return write(data, to: url)
    }

    private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url)
            return true
        } catch {
            print(T("写不了 %@：%@", ["\(url.lastPathComponent)", "\(error.localizedDescription)"]))
            return false
        }
    }
}
