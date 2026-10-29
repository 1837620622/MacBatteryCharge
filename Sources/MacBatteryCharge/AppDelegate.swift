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
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    /// 找不到菜单栏图标时（被挤掉、被刘海挡住），弹窗挂在屏幕右上角这个看不见的小窗上。
    private var fallbackAnchor: NSWindow?
    private var powerSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var island: NotchIsland?
    private var settingsSink: AnyCancellable?
    private var lastIconKey = ""
    /// `--selftest-menubar 报告路径`：CI 用。有这个就不自动开窗口，改成模拟点击菜单栏图标，把结果写进报告后退出。
    var selfTestReport: URL?
    private var selfTestLines: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let background = LaunchContext.isBackgroundLaunch()
        if LaunchContext.anotherInstanceRunning() {
            DistributedNotificationCenter.default().postNotificationName(showWindowNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        Log.installCrashHandler()
        Log.beginSession()
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
            .sink { [weak island] _ in Task { @MainActor in island?.configure() } }
        model.start()

        LoginItem.removeLegacyAgent(launchedByAgent: CommandLine.arguments.contains("--background"))
        model.syncLogin()

        if selfTestReport != nil {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.runMenuBarSelfTest()
            }
        } else if !background {
            showPopover()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveNow()
        model.releaseHelper()
        Log.endSession()
    }

    @objc private func showFromOtherProcess(_ notification: Notification) {
        showPopover()
    }

    // MARK: 菜单栏

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MacBatteryChargeStatusItem"
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            // 在按下时响应。弹窗开着时点图标，点击本身就会先把弹窗收掉；要是等松开再判断，就会又被打开。
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.imagePosition = .imageOnly
        }
        statusItem = item
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let battery = model.battery
        let charging = battery.flow == .charging
        // 两秒读一次时，图标没变就不重画。
        let key = "\(battery.percent ?? -1)|\(charging)"
        if key != lastIconKey {
            lastIconKey = key
            button.image = MenuBarIcon.image(percent: battery.percent, charging: charging)
        }
        let percent = battery.percent.map { T("电量 %@%，", ["\($0)"]) } ?? ""
        button.setAccessibilityLabel(T("充电上限 %@，%@%@", ["\(model.menuTop)", "\(percent)", "\(model.menuBottom)"]))
        button.toolTip = "\(model.limitLine)\n\(model.statusTitle)"
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true {
            showMenu(from: sender)
        } else {
            togglePopover()
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let battery = model.battery
        let header = NSMenuItem(title: battery.percent.map { T("电量 %@% · %@", ["\($0)", "\(model.limitLine)"]) } ?? model.limitLine, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(withTitle: T("打开窗口"), action: #selector(openFromMenu), keyEquivalent: "").target = self
        let topUp = menu.addItem(withTitle: model.topUpActive ? T("结束临时充满") : T("临时充满到 100%"), action: #selector(toggleTopUp), keyEquivalent: "")
        topUp.target = self
        topUp.isEnabled = model.topUpAvailable
        let apply = menu.addItem(withTitle: T("立即应用"), action: #selector(applyFromMenu), keyEquivalent: "")
        apply.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: T("关于充电上限"), action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: T("退出充电上限"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openFromMenu() { showPopover() }
    @objc private func toggleTopUp() { model.toggleTopUp() }
    @objc private func applyFromMenu() { model.applyNow() }

    /// 系统自带的“关于”面板，写上作者和项目地址。
    @objc private func showAbout() {
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11)]
        let credits = NSMutableAttributedString(string: T("作者 %@", ["\(AppInfo.author)"]) + "\n", attributes: small)
        var link = small
        link[.link] = AppInfo.homepage
        credits.append(NSAttributedString(string: AppInfo.homepage.absoluteString, attributes: link))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: Installation.version,
            .version: "",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): AppInfo.copyright,
        ])
    }

    // MARK: 弹窗

    /// 再点一下图标：弹窗开着就收起，没开就打开。
    private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    /// 从菜单栏图标下面打开弹窗。每次都从主页开始，不停在上次的设置页。
    func showPopover() {
        let popover = self.popover ?? makePopover()
        self.popover = popover
        if !popover.isShown {
            popover.contentViewController = makeContent()
            popover.contentSize = RootView.popoverSize
            if let button = statusItem?.button, button.window != nil {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            } else {
                showFallbackPopover(popover)
            }
        }
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        popover.contentViewController?.view.window?.makeKey()
        model.windowVisible = true
        model.windowDidOpen()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        // 点别处就收起，和系统自带的菜单栏弹窗一样。
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        return popover
    }

    private func makeContent() -> NSHostingController<RootView> {
        let hosting = NSHostingController(rootView: RootView(model: model))
        hosting.sizingOptions = []
        return hosting
    }

    /// 图标找不到时：在屏幕右上角放一个看不见的小窗，弹窗挂在它下面。
    private func showFallbackPopover(_ popover: NSPopover) {
        guard let screen = NSScreen.main else { return }
        let anchor = fallbackAnchor ?? makeFallbackAnchor()
        fallbackAnchor = anchor
        anchor.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 200, y: screen.visibleFrame.maxY - 1))
        anchor.orderFrontRegardless()
        if let view = anchor.contentView {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    private func makeFallbackAnchor() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        return window
    }

    func popoverDidClose(_ notification: Notification) {
        fallbackAnchor?.orderOut(nil)
        model.windowVisible = false
        model.saveNow()
        model.editingID = nil
    }

    // MARK: 自检

    /// 模拟用户点两次菜单栏图标，看弹窗开了、又收起来了。只给 CI 用。
    private func runMenuBarSelfTest() {
        let button = statusItem?.button
        selfTestLines.append("状态栏图标在屏幕上：\(button?.window != nil ? "通过" : "失败")")
        button?.performClick(nil)
        selfTestLines.append("第一次点击后弹窗打开：\(popover?.isShown == true ? "通过" : "失败")")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.finishMenuBarSelfTest()
        }
    }

    private func finishMenuBarSelfTest() {
        let visible = popover?.contentViewController?.view.window?.isVisible == true
        selfTestLines.append("弹窗窗口可见：\(visible ? "通过" : "失败")")
        statusItem?.button?.performClick(nil)
        selfTestLines.append("第二次点击后弹窗收起：\(popover?.isShown == true ? "失败" : "通过")")
        let passed = !selfTestLines.contains { $0.hasSuffix("失败") }
        selfTestLines.append(passed ? "结果：通过" : "结果：失败")
        if let report = selfTestReport {
            try? (selfTestLines.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8)
        }
        NSApp.terminate(nil)
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
