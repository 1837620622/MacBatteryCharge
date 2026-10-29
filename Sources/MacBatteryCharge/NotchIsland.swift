import AppKit
import SwiftUI
import BatteryCore

/// 屏幕上刘海的位置和大小。没有刘海时按菜单栏正中虚拟一个。
struct NotchGeometry: Equatable {
    var screenFrame: NSRect
    var width: CGFloat
    var height: CGFloat
    var real: Bool

    var rect: NSRect {
        NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }

    static func of(_ screen: NSScreen, virtual: Bool) -> NotchGeometry? {
        let top = screen.safeAreaInsets.top
        if top > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let width = left > 0 && right > 0 ? screen.frame.width - left - right : 200
            return NotchGeometry(screenFrame: screen.frame, width: width, height: top, real: true)
        }
        guard virtual else { return nil }
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return NotchGeometry(screenFrame: screen.frame, width: 170, height: menuBar, real: false)
    }
}

@MainActor
final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var geometry = NotchGeometry(screenFrame: .zero, width: 200, height: 32, real: true)
    @Published var ears = false
}

/// 刘海灵动岛。鼠标移到刘海、插拔电源时从刘海里长出一块黑色面板。
/// 只用鼠标位置，不要辅助功能、屏幕录制或输入监控。
@MainActor
final class NotchIsland {
    static let panelSize = NSSize(width: 400, height: 190)
    static let earWidth: CGFloat = 66

    private let model: AppModel
    private let state = IslandState()
    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var enterTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var peekUntil = Date.distantPast
    private var active = false

    init(model: AppModel) {
        self.model = model
    }

    /// 设置变了就调一次。
    func configure() {
        let settings = model.settings
        let wanted = settings.notchIsland || settings.notchEars
        state.ears = settings.notchEars
        if wanted && !active { start() }
        if !wanted && active { stop() }
        if active { reposition() }
    }

    func peek(seconds: Double = 4) {
        guard active, model.settings.notchOnPower else { return }
        peekUntil = Date().addingTimeInterval(seconds)
        setExpanded(true)
        leaveTask?.cancel()
        leaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.collapseIfOutside()
        }
    }

    // MARK: 开关

    private func start() {
        active = true
        let panel = makePanel()
        self.panel = panel
        reposition()
        panel.orderFrontRegardless()

        if model.settings.notchIsland {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                Task { @MainActor in self?.mouseMoved() }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                Task { @MainActor in self?.mouseMoved() }
                return event
            }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    private func stop() {
        active = false
        enterTask?.cancel()
        leaveTask?.cancel()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        globalMonitor = nil
        localMonitor = nil
        screenObserver = nil
        panel?.orderOut(nil)
        panel = nil
        state.expanded = false
        model.islandOpen = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = NSHostingView(rootView: IslandView(model: model, state: state, onOpen: { [weak self] in
            self?.openWindow()
        }))
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }

    private func targetScreen() -> NSScreen? {
        let settings = model.settings
        // 优先放在有真刘海的屏幕上。
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) { return notched }
        return settings.notchWithoutNotch ? (NSScreen.main ?? NSScreen.screens.first) : nil
    }

    private func reposition() {
        guard let panel else { return }
        guard let screen = targetScreen(), let geometry = NotchGeometry.of(screen, virtual: model.settings.notchWithoutNotch) else {
            panel.orderOut(nil)
            return
        }
        state.geometry = geometry
        let size = Self.panelSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    // MARK: 鼠标

    private var hotRect: NSRect {
        var rect = state.geometry.rect
        if state.ears { rect = rect.insetBy(dx: -Self.earWidth, dy: 0) }
        return rect.insetBy(dx: -4, dy: -1)
    }

    private var expandedRect: NSRect {
        let geometry = state.geometry
        let width = IslandView.expandedWidth
        return NSRect(x: geometry.screenFrame.midX - width / 2 - 8,
                      y: geometry.screenFrame.maxY - IslandView.expandedHeight(for: geometry) - 8,
                      width: width + 16, height: IslandView.expandedHeight(for: geometry) + 8)
    }

    private func mouseMoved() {
        let point = NSEvent.mouseLocation
        if state.expanded {
            if expandedRect.contains(point) {
                leaveTask?.cancel()
                leaveTask = nil
            } else if leaveTask == nil {
                scheduleLeave()
            }
        } else if hotRect.contains(point) {
            if enterTask == nil {
                enterTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(160))
                    guard let self, !Task.isCancelled else { return }
                    self.enterTask = nil
                    if self.hotRect.contains(NSEvent.mouseLocation) { self.setExpanded(true) }
                }
            }
        } else {
            enterTask?.cancel()
            enterTask = nil
        }
    }

    private func scheduleLeave() {
        leaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            self.leaveTask = nil
            self.collapseIfOutside()
        }
    }

    private func collapseIfOutside() {
        leaveTask = nil
        if Date() < peekUntil { return }
        if expandedRect.contains(NSEvent.mouseLocation) { return }
        setExpanded(false)
    }

    private func setExpanded(_ value: Bool) {
        guard state.expanded != value else { return }
        panel?.ignoresMouseEvents = !value
        model.islandOpen = value
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            state.expanded = value
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { state.expanded = value }
        }
    }

    private func openWindow() {
        (NSApp.delegate as? AppDelegate)?.showWindow()
    }
}

/// 上面平、下面两个圆角的形状，和刘海的轮廓连成一块。
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct IslandView: View {
    static let expandedWidth: CGFloat = 380

    static func expandedHeight(for geometry: NotchGeometry) -> CGFloat { geometry.height + 124 }

    @ObservedObject var model: AppModel
    @ObservedObject var state: IslandState
    var onOpen: () -> Void

    var body: some View {
        let geometry = state.geometry
        let expanded = state.expanded
        let collapsedWidth = geometry.width + (state.ears ? NotchIsland.earWidth * 2 : 0)
        let width = expanded ? Self.expandedWidth : collapsedWidth
        let height = expanded ? Self.expandedHeight(for: geometry) : geometry.height

        ZStack(alignment: .top) {
            NotchShape(bottomRadius: expanded ? 26 : (geometry.real ? 10 : 12))
                .fill(Color.black)
                .frame(width: width, height: height)

            if expanded {
                content(geometry)
                    .frame(width: Self.expandedWidth, height: height, alignment: .top)
                    .transition(.opacity)
            } else if state.ears {
                ears(geometry)
                    .frame(width: collapsedWidth, height: geometry.height)
                    .transition(.opacity)
            }
        }
        .frame(width: NotchIsland.panelSize.width, height: NotchIsland.panelSize.height, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private func ears(_ geometry: NotchGeometry) -> some View {
        HStack(spacing: 0) {
            Text(model.menuTop)
                .frame(width: NotchIsland.earWidth)
            Spacer(minLength: geometry.width)
            Text(model.menuBottom)
                .frame(width: NotchIsland.earWidth)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.92))
    }

    private func content(_ geometry: NotchGeometry) -> some View {
        let battery = model.battery
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.14), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: Double(battery.percent ?? 0) / 100)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(battery.percent.map { "\($0)" } ?? "—")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.statusTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(model.limitLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                    if let tonight = model.tonight {
                        Text(tonight.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                islandButton(model.topUpActive ? T("结束临时充满") : T("临时充满"), symbol: "bolt.fill") { model.toggleTopUp() }
                    .disabled(!battery.present)
                islandButton(T("打开窗口"), symbol: "macwindow") { onOpen() }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, geometry.height + 8)
    }

    private var ringColor: Color {
        switch model.battery.flow {
        case .charging: return .green
        case .discharging: return (model.battery.percent ?? 100) <= 20 ? .red : .orange
        default: return .accentColor
        }
    }

    private func islandButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
