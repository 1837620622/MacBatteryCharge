import AppKit
import SwiftUI
import IOKit.ps
import Combine
import BatteryCore

extension Notification.Name {
    static let powerSourceChanged = Notification.Name("MBCPowerSourceChanged")
}

/// 其他进程要求打开窗口时用：第二次打开程序、或者旧版的启动项。
let showWindowNotification = Notification.Name("com.macbatterycharge.show")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var powerSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var island: NotchIsland?
    private var settingsSink: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let background = LaunchContext.isBackgroundLaunch()
        if LaunchContext.anotherInstanceRunning() {
            DistributedNotificationCenter.default().postNotificationName(showWindowNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showFromOtherProcess(_:)), name: showWindowNotification, object: nil)
        setUpStatusItem()
        watchPower()

        model.onStatusChange = { [weak self] in self?.updateStatusItem() }
        let island = NotchIsland(model: model)
        self.island = island
        model.onPlugChange = { [weak island] _ in island?.peek() }
        island.configure()
        settingsSink = model.$settings
            .map { [$0.notchIsland, $0.notchOnPower, $0.notchEars, $0.notchWithoutNotch] }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak island] _ in DispatchQueue.main.async { island?.configure() } }
        model.start()

        LoginItem.removeLegacyAgent(launchedByAgent: CommandLine.arguments.contains("--background"))
        model.syncLogin()

        if !background { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveNow()
        model.releaseHelper()
    }

    @objc private func showFromOtherProcess(_ notification: Notification) {
        showWindow()
    }

    // MARK: 菜单栏

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MacBatteryChargeStatusItem"
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        statusItem = item
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let battery = model.battery
        button.image = MenuBarIcon.image(top: model.menuTop, bottom: model.menuBottom,
                                         level: battery.percent.map { Double($0) / 100 },
                                         charging: battery.flow == .charging)
        let percent = battery.percent.map { "电量 \($0)%，" } ?? ""
        button.setAccessibilityLabel("充电上限 \(model.menuTop)，\(percent)\(model.menuBottom)")
        button.toolTip = "\(model.limitLine)\n\(model.statusTitle)"
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu(from: sender)
        } else {
            toggleWindow()
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let battery = model.battery
        let header = NSMenuItem(title: battery.percent.map { "电量 \($0)% · \(model.limitLine)" } ?? model.limitLine, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开窗口", action: #selector(openFromMenu), keyEquivalent: "").target = self
        let topUp = menu.addItem(withTitle: model.topUpActive ? "结束临时充满" : "临时充满到 100%", action: #selector(toggleTopUp), keyEquivalent: "")
        topUp.target = self
        topUp.isEnabled = battery.present
        let apply = menu.addItem(withTitle: "立即应用", action: #selector(applyFromMenu), keyEquivalent: "")
        apply.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出充电上限", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openFromMenu() { showWindow() }
    @objc private func toggleTopUp() { model.toggleTopUp() }
    @objc private func applyFromMenu() { model.applyNow() }

    // MARK: 窗口

    private func toggleWindow() {
        if let window, window.isVisible, window.isKeyWindow, NSApp.isActive {
            window.performClose(nil)
        } else {
            showWindow()
        }
    }

    func showWindow() {
        let window = self.window ?? makeWindow()
        self.window = window
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window.makeKeyAndOrderFront(nil)
        model.windowVisible = true
        model.windowDidOpen()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: RootView(model: model))
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 760),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "充电上限"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.minSize = NSSize(width: 400, height: 520)
        window.maxSize = NSSize(width: 560, height: 4000)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        window.delegate = self
        if !window.setFrameUsingName("MainWindow") { place(window) }
        window.setFrameAutosaveName("MainWindow")
        return window
    }

    /// 第一次打开时放在菜单栏图标下面。
    private func place(_ window: NSWindow) {
        guard let buttonWindow = statusItem?.button?.window, let screen = buttonWindow.screen ?? NSScreen.main else {
            window.center()
            return
        }
        let anchor = buttonWindow.frame
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.height = min(frame.height, visible.height - 16)
        frame.origin.x = min(max(anchor.midX - frame.width / 2, visible.minX + 8), visible.maxX - frame.width - 8)
        frame.origin.y = visible.maxY - frame.height - 8
        window.setFrame(frame, display: false)
    }

    func windowWillClose(_ notification: Notification) {
        model.windowVisible = false
        model.saveNow()
        model.editingID = nil
    }

    // MARK: 电源变化

    private func watchPower() {
        // 插拔电源、电量变化时系统会通知，不用干等 30 秒。
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(name: .powerSourceChanged, object: nil)
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .powerSourceChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        })
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        })
    }
}

enum LaunchContext {
    /// 登录时由系统带起来，或者旧版启动项加了 --background：不开窗口，也不查更新。
    static func isBackgroundLaunch() -> Bool {
        if CommandLine.arguments.contains("--background") { return true }
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        let openApplication: AEEventID = 0x6F61_7070 // 'oapp'
        let propData: AEKeyword = 0x7072_6474 // 'prdt'
        let launchedAsLogInItem: OSType = 0x6C67_6974 // 'lgit'
        return event.eventID == openApplication
            && event.paramDescriptor(forKeyword: propData)?.enumCodeValue == launchedAsLogInItem
    }

    static func anotherInstanceRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { $0.processIdentifier != me }
    }
}
