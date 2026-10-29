import AppKit
import SwiftUI
import BatteryCore

/// `--snapshot 目录`：用假数据把主窗口、六步引导和菜单栏图标画成 PNG，给 CI 看界面用。不读也不改这台 Mac 的任何设置。
enum Snapshot {
    @MainActor
    static func run(to directory: URL) -> Bool {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("建不了目录：\(error.localizedDescription)")
            return false
        }

        var ok = true
        let folds = ["top", "bottom", "history", "schedule", "helper", "smart", "look", "system"]
        func setFolds(_ values: [String: Bool]) {
            for key in folds { UserDefaults.standard.set(values[key] ?? true, forKey: "fold.\(key)") }
        }
        func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let model = sampleModel()

            // 三种质感，每种都先全展开。
            for look in WindowLook.allCases {
                model.settings.look = look
                setFolds([:])
                ok = render(RootView(model: model), size: NSSize(width: 420, height: 760), appearance: appearance,
                            to: file("main-\(look.rawValue)-\(name).png")) && ok
            }
            model.settings.look = .frosted

            setFolds([:])
            ok = render(MainView(model: model).environment(\.windowLook, .frosted).environment(\.isPreview, true)
                .background(WindowBackdrop(look: .frosted, transparency: model.settings.transparency, preview: true))
                .frame(width: 420, height: 2300), size: NSSize(width: 420, height: 2300), appearance: appearance,
                        to: file("main-full-\(name).png")) && ok

            // 第一层收起；只收第二层。
            setFolds(["top": false, "bottom": false])
            ok = render(RootView(model: model), size: NSSize(width: 420, height: 480), appearance: appearance,
                        to: file("main-folded-\(name).png")) && ok
            setFolds(["history": false, "schedule": true, "helper": false, "smart": false, "look": false, "system": false])
            ok = render(RootView(model: model), size: NSSize(width: 420, height: 900), appearance: appearance,
                        to: file("main-cards-folded-\(name).png")) && ok
            setFolds([:])

            // 设置里最长的两块，单独看。
            ok = render(RootView(model: model), size: NSSize(width: 420, height: 760), appearance: appearance,
                        to: file("main-top-\(name).png")) && ok

            ok = render(islandPreview(model: model, expanded: true), size: NotchIsland.panelSize, appearance: .darkAqua,
                        to: file("island-expanded-\(name).png")) && ok
            ok = render(islandPreview(model: model, expanded: false), size: NotchIsland.panelSize, appearance: .darkAqua,
                        to: file("island-ears-\(name).png")) && ok
            for step in GuideCopy.titles.indices {
                let guide = GuideView(model: model, startStep: step, fixedPhase: 0.8)
                    .background(WindowBackdrop(look: .frosted, transparency: 0.25, preview: true))
                    .environment(\.windowLook, .frosted)
                ok = render(guide, size: NSSize(width: 420, height: 640), appearance: appearance,
                            to: file("guide-\(step + 1)-\(name).png")) && ok
            }
            ok = writeMenuBar(dark: appearance == .darkAqua, to: file("menubar-\(name).png")) && ok
        }
        print(ok ? "截图在 \(directory.path)" : "有截图没画出来")
        return ok
    }

    // MARK: 假数据

    @MainActor
    static func sampleModel() -> AppModel {
        let model = AppModel(preview: true)
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 14, minute: 10, second: 0, of: Date()) ?? Date()
        let schedule = model.schedule

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
                                    lowPower: LowPowerState(battery: 0, ac: 0), thermal: .nominal, date: now, helper: helper)
        model.loadPreview(reading, history: sampleHistory(ending: now, schedule: schedule), minute: currentMinute(now))
        return model
    }

    /// 按默认作息模拟 24 小时：白天停在 80%，21:00 后充到 100%，23:30 断电用电池，06:00 来电。
    static func sampleHistory(ending end: Date, schedule: Schedule) -> ChargeHistory {
        var history = ChargeHistory()
        var percent = 80.0
        var time = end.addingTimeInterval(-24 * 3600)
        while time <= end {
            let minute = currentMinute(time)
            let plugged = minute >= 6 * 60 && minute < 23 * 60 + 30
            let limit = schedule.limit(at: minute)
            var charging = false
            if plugged {
                if percent < Double(limit) {
                    percent = min(Double(limit), percent + 2.2)
                    charging = true
                }
            } else {
                percent -= minute >= 23 * 60 + 30 || minute < 2 * 60 ? 1.6 : 0.1
            }
            history.add(ChargeSample(t: time, p: Int(percent.rounded()), c: charging, x: plugged, l: limit))
            time = time.addingTimeInterval(600)
        }
        for day in 0..<60 {
            let date = end.addingTimeInterval(Double(day - 59) * 86_400)
            history.addHealth(HealthPoint(day: AppModel.dayFormatter.string(from: date), health: 93 - day / 20, cycles: 160 + day))
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

    // MARK: 画图

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
            print("画不出 \(url.lastPathComponent)")
            return false
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
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

    /// 菜单栏图标的几种状态排成一行。
    @MainActor
    static func writeMenuBar(dark: Bool, to url: URL) -> Bool {
        let states: [(String, String, Double?, Bool)] = [
            ("80%", "接通", 0.8, false),
            ("100%", "充电", 0.86, true),
            ("80%", "电池", 0.62, false),
            ("100%", "放电", 0.35, false),
            ("—", "无电池", nil, false),
        ]
        let icons = states.map { MenuBarIcon.image(top: $0.0, bottom: $0.1, level: $0.2, charging: $0.3) }
        let gap: CGFloat = 18
        let width = icons.reduce(gap) { $0 + $1.size.width + gap }
        let size = NSSize(width: width, height: 30)
        let ink: NSColor = dark ? .white : .black
        let background = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 3), pixelsHigh: Int(size.height * 3),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        background.setFill()
        NSRect(origin: .zero, size: size).fill()
        var x = gap
        for icon in icons {
            let tinted = NSImage(size: icon.size, flipped: false) { rect in
                icon.draw(in: rect)
                ink.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: x, y: (size.height - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
            x += icon.size.width + gap
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return write(data, to: url)
    }

    private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url)
            return true
        } catch {
            print("存不了 \(url.lastPathComponent)：\(error.localizedDescription)")
            return false
        }
    }
}
