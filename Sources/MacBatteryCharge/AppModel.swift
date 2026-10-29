import AppKit
import SwiftUI
import BatteryCore

@MainActor
final class AppModel: ObservableObject {
    struct Message: Equatable {
        enum Tone: Equatable {
            case info
            case success
            case error
        }

        var tone: Tone
        var text: String
    }

    /// 窗口顶上的「今晚」卡片。
    struct Tonight: Equatable {
        var title: String
        var detail: String
        var symbol: String
        var tone: Message.Tone
    }

    @Published var settings: AppSettings {
        didSet { settingsChanged(from: oldValue) }
    }

    @Published private(set) var reading: SystemReading?
    @Published private(set) var history = ChargeHistory()
    @Published private(set) var decision = LimitDecision(limit: 100, reason: .gap, scheduled: 100)
    @Published private(set) var heatActive = false
    @Published private(set) var topUpUntil: Date?
    @Published private(set) var deadlineLift: (target: Int, until: Date)?
    @Published private(set) var message: Message?
    @Published private(set) var applying = false
    @Published private(set) var update: UpdateState = .idle
    @Published private(set) var loginState: LoginItem.State = .off
    @Published private(set) var loginNote: String?
    @Published private(set) var minute = currentMinute()
    @Published private(set) var schedule: Schedule
    @Published private(set) var scheduleError: ScheduleError?
    @Published private(set) var moving = false
    @Published var showGuide: Bool
    @Published var editingID: Interval.ID?

    /// 菜单栏要跟着变。
    var onStatusChange: (() -> Void)?
    let preview: Bool

    private var lastValidIntervals: [Interval]
    private var timer: Task<Void, Never>?
    private var refreshing = false
    private var refreshAgain = false
    private var writingLimit = false
    private var failedWrite: (limit: Int, at: Date)?
    private var saveTask: Task<Void, Never>?
    private var lastFlow: PowerFlow?
    private var wasExternal = false
    private var lastHistorySave = Date.distantPast
    private var pollTask: Task<Void, Never>?
    private var lastProgress = -1.0

    init(preview: Bool = false) {
        self.preview = preview
        let loaded = preview ? AppSettings() : AppSettings.load()
        var start = loaded
        if preview { start.guideSeen = true }
        settings = start
        showGuide = !start.guideSeen
        lastValidIntervals = start.intervals
        switch Schedule.compile(start.intervals) {
        case .success(let compiled):
            schedule = compiled
        case .failure(let error):
            schedule = (try? Schedule.compile(Schedule.makeDefaults()).get()) ?? .empty
            scheduleError = error
        }
        if !preview {
            history = ChargeHistory.load(from: AppSettings.historyURL)
            loginState = LoginItem.state
        }
        recompute()
    }

    // MARK: 读数

    var battery: BatterySnapshot { reading?.battery ?? BatterySnapshot() }
    var currentInterval: Interval? { schedule.interval(at: minute) }
    var currentIndex: Int? { schedule.index(at: minute) }
    var wantedLowPower: LowPowerChoice { schedule.lowPower(at: minute) }

    var lowPowerMismatch: Bool {
        guard let state = reading?.lowPower else { return false }
        return !state.matches(wantedLowPower)
    }

    var systemLimitMismatch: Bool {
        guard let value = reading?.chargeLimit.value else { return false }
        return value != decision.limit
    }

    var advice: [AdviceItem] {
        Advice.items(battery: battery, memory: reading?.memory ?? MemorySnapshot(),
                     limit: reading?.chargeLimit.isSupported == true ? decision.limit : nil,
                     heatActive: heatActive)
    }

    var learnedRate: Double? { history.learnedRate() }

    // MARK: 生命周期

    func start() {
        guard !preview, timer == nil else { return }
        refresh()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard !preview else { return }
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        Task.detached(priority: .utility) {
            let value = SystemReaders.read()
            await self.receive(value)
        }
    }

    private func receive(_ value: SystemReading) {
        refreshing = false
        reading = value
        minute = currentMinute(value.date)
        let battery = value.battery

        heatActive = settings.heatProtection
            ? ChargePolicy.heatActive(previous: heatActive, celsius: battery.celsius, external: battery.externalConnected)
            : false

        // 临时充满和提前放开都在拔掉电源时结束。
        if wasExternal && !battery.externalConnected {
            topUpUntil = nil
            deadlineLift = nil
        }
        wasExternal = battery.externalConnected
        if let until = topUpUntil, value.date >= until { topUpUntil = nil }
        if let lift = deadlineLift, value.date >= lift.until || !settings.deadlineEnabled { deadlineLift = nil }

        if settings.deadlineEnabled, battery.externalConnected, deadlineLift == nil, let percent = battery.percent,
           let plan = ChargePlanner.plan(schedule: schedule, minute: minute, percent: percent,
                                         deadline: settings.deadline, rate: learnedRate), plan.liftNow {
            deadlineLift = (plan.target, value.date.addingTimeInterval(Double(plan.minutesToDeadline) * 60))
            notify("deadline", "提前放开到 \(plan.target)%", "按这台机器的充电速度，赶在 \(settings.deadline.text) 断电前充满。")
        }

        let previousHeat = decision.reason == .heat
        recompute()
        if decision.reason == .heat && !previousHeat {
            notify("heat", "电池偏热，先停在 80%", "降到 37°C 以下再按时间表继续。")
        }

        let flow = battery.flow
        if lastFlow == .charging && flow == .plugged, let percent = battery.percent, percent >= decision.limit - 1 {
            notify("limit", "已停在 \(percent)%", "电源直接供电，电池不再往上充。")
        }
        lastFlow = flow

        record(value)
        autoApplyLimit()
        onStatusChange?()
        if refreshAgain {
            refreshAgain = false
            refresh()
        }
    }

    private func recompute() {
        decision = ChargePolicy.decide(schedule: schedule, minute: minute, topUp: topUpUntil != nil,
                                       deadlineLift: deadlineLift?.target, heat: heatActive)
    }

    private func record(_ value: SystemReading) {
        guard let percent = value.battery.percent, value.battery.present else { return }
        history.add(ChargeSample(t: value.date, p: percent, c: value.battery.flow == .charging,
                                 x: value.battery.externalConnected, l: decision.limit))
        if let health = value.battery.health {
            history.addHealth(HealthPoint(day: Self.dayFormatter.string(from: value.date), health: health, cycles: value.battery.cycles))
        }
        if value.date.timeIntervalSince(lastHistorySave) >= 240 {
            lastHistorySave = value.date
            let copy = history
            Task.detached(priority: .background) { try? copy.save(to: AppSettings.historyURL) }
        }
    }

    /// 换段、临时充满、提前放开、过热保护都在这里写给系统。不要密码。
    /// 系统设置里被改过也会改回时间表的值。
    private func autoApplyLimit() {
        guard !preview, !writingLimit, let current = reading?.chargeLimit.value, current != decision.limit else { return }
        let limit = decision.limit
        if let failed = failedWrite, failed.limit == limit, Date().timeIntervalSince(failed.at) < 300 { return }
        writingLimit = true
        Task {
            let error = await Task.detached { ChargeBridge.write(limit) }.value
            writingLimit = false
            if let error {
                failedWrite = (limit, Date())
                message = Message(tone: .error, text: "充电上限没写上：\(error)")
            } else {
                failedWrite = nil
            }
            refresh()
        }
    }

    // MARK: 设置

    private func settingsChanged(from old: AppSettings) {
        if settings.intervals != old.intervals {
            switch Schedule.compile(settings.intervals) {
            case .success(let compiled):
                schedule = compiled
                scheduleError = nil
                lastValidIntervals = settings.intervals
            case .failure(let error):
                scheduleError = error
            }
        }
        if settings.heatProtection != old.heatProtection && !settings.heatProtection { heatActive = false }
        if settings.deadlineEnabled != old.deadlineEnabled || settings.deadline != old.deadline { deadlineLift = nil }
        if settings.launchAtLogin != old.launchAtLogin { syncLogin() }
        if settings.notifications && !old.notifications {
            Notifier.requestAuthorization { granted in
                Task { @MainActor in
                    if !granted {
                        self.settings.notifications = false
                        self.message = Message(tone: .info, text: "通知没有打开。可以在系统设置的“通知”里允许充电上限。")
                    }
                }
            }
        }
        recompute()
        onStatusChange?()
        scheduleSave()
        if !preview && settings.intervals != old.intervals { autoApplyLimit() }
    }

    private func scheduleSave() {
        guard !preview else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { saveNow() }
        }
    }

    /// 时间表有错时，文件里保留上一次能用的时间表。
    func saveNow() {
        guard !preview else { return }
        var copy = settings
        if scheduleError != nil { copy.intervals = lastValidIntervals }
        do {
            try copy.save()
        } catch {
            message = Message(tone: .error, text: "设置没有存上：\(error.localizedDescription)")
        }
    }

    func syncLogin() {
        guard !preview else { return }
        loginNote = LoginItem.sync(enabled: settings.launchAtLogin)
        loginState = LoginItem.state
    }

    func refreshLoginState() {
        guard !preview else { return }
        loginState = LoginItem.state
        if loginState == .on || !settings.launchAtLogin { loginNote = nil }
    }

    // MARK: 时间表编辑

    var canAddInterval: Bool {
        settings.intervals.count < Schedule.maxIntervals && scheduleError == nil
            && Schedule.firstFreeSlot(in: settings.intervals) != nil
    }

    var addHint: String? {
        if settings.intervals.count >= Schedule.maxIntervals { return "最多 \(Schedule.maxIntervals) 段" }
        if scheduleError != nil { return "先改好上面的问题" }
        if Schedule.firstFreeSlot(in: settings.intervals) == nil { return "一天已经排满，先缩短一段再加" }
        return nil
    }

    func addInterval() {
        guard canAddInterval, let slot = Schedule.firstFreeSlot(in: settings.intervals) else { return }
        let item = Interval(start: slot.start, end: slot.end, limit: 100, lowPower: .off)
        settings.intervals.append(item)
        settings.intervals.sort { $0.start < $1.start }
        editingID = item.id
    }

    func removeInterval(_ id: Interval.ID) {
        settings.intervals.removeAll { $0.id == id }
        if editingID == id { editingID = nil }
    }

    func resetSchedule() {
        settings.intervals = Schedule.makeDefaults()
        editingID = nil
    }

    func sortIntervals() {
        settings.intervals.sort { $0.start < $1.start }
    }

    // MARK: 临时充满

    var topUpActive: Bool { topUpUntil != nil }

    func toggleTopUp() {
        if topUpUntil != nil {
            topUpUntil = nil
        } else {
            let ahead = schedule.minutesUntilBoundary(from: minute) ?? 1440
            topUpUntil = Date().addingTimeInterval(Double(ahead) * 60)
        }
        recompute()
        onStatusChange?()
        autoApplyLimit()
    }

    // MARK: 立即应用

    func applyNow() {
        guard !applying, !preview else { return }
        if let error = scheduleError {
            message = Message(tone: .error, text: "\(error.message)。改好之后再应用。")
            return
        }
        applying = true
        saveNow()
        let wanted = wantedLowPower
        let hasBattery = battery.present
        Task {
            var notes: [String] = []
            var tone = Message.Tone.success
            let limit = decision.limit
            switch await Task.detached(operation: { ChargeBridge.read() }).value {
            case .current(let value) where value == limit:
                notes.append("充电上限已是 \(limit)%")
            case .current:
                if let error = await Task.detached(operation: { ChargeBridge.write(limit) }).value {
                    notes.append("充电上限没写上：\(error)")
                    tone = .error
                } else {
                    notes.append("充电上限改为 \(limit)%")
                }
            case .unsupported(let text):
                notes.append(text)
                tone = .info
            case .unknown:
                break
            }

            let current = await Task.detached(operation: { SystemReaders.lowPower() }).value
            if let current, current.matches(wanted) {
                notes.append("低电量已是「\(wanted.title)」")
            } else {
                let key = current?.key ?? "lowpowermode"
                switch await Task.detached(operation: { LowPowerWriter.apply(wanted, key: key, hasBattery: hasBattery) }).value {
                case .done:
                    notes.append("低电量改为「\(wanted.title)」")
                case .cancelled:
                    notes.append("密码框取消了，低电量没有改")
                    if tone == .success { tone = .info }
                case .failed(let text):
                    notes.append("低电量没有改：\(text)")
                    tone = .error
                }
            }

            syncLogin()
            if let note = loginNote { notes.append(note.trimmingCharacters(in: CharacterSet(charactersIn: "。"))) }
            message = Message(tone: tone, text: notes.joined(separator: "。") + "。")
            applying = false
            failedWrite = nil
            refresh()
        }
    }

    func dismissMessage() { message = nil }

    // MARK: 窗口

    func windowDidOpen() {
        refresh()
        refreshLoginState()
        maybeCheckForUpdates()
    }

    func finishGuide() {
        settings.guideSeen = true
        showGuide = false
        saveNow()
        maybeCheckForUpdates()
    }

    func replayGuide() {
        showGuide = true
    }

    // MARK: 更新

    /// 只在窗口打开、引导看完后才查。登录时后台启动不查，也不弹窗。
    func maybeCheckForUpdates() {
        guard !preview, settings.guideSeen, !showGuide, settings.autoCheckUpdates else { return }
        switch update {
        case .idle, .upToDate, .failed: break
        default: return
        }
        if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < 20 * 3600 { return }
        checkForUpdates(userInitiated: false)
    }

    func checkForUpdates(userInitiated: Bool) {
        guard !preview else { return }
        if userInitiated { update = .checking }
        Task {
            do {
                let release = try await UpdateCheck.fetchLatest()
                settings.lastUpdateCheck = Date()
                if AppVersion.isNewer(release.version, than: Installation.version) {
                    update = (!userInitiated && settings.skippedVersion == release.version) ? .idle : .available(release)
                } else {
                    update = userInitiated ? .upToDate : .idle
                }
            } catch {
                update = userInitiated ? .failed("查不到新版本：\(error.localizedDescription)") : .idle
            }
        }
    }

    func skip(_ release: ReleaseInfo) {
        settings.skippedVersion = release.version
        update = .idle
    }

    func install(_ release: ReleaseInfo) {
        guard let asset = release.package(arm64: SystemReaders.isAppleSilicon) else {
            if let page = release.page { NSWorkspace.shared.open(page) }
            return
        }
        update = .downloading(release, 0)
        lastProgress = -1
        let destination = UpdateCheck.cacheDirectory.appendingPathComponent(asset.name)
        let downloader = PackageDownloader(
            destination: destination,
            onProgress: { value in Task { @MainActor in self.downloadProgress(release, value) } },
            onFinish: { result in Task { @MainActor in self.downloadFinished(release, asset, result) } }
        )
        downloader.start(asset.url)
    }

    private func downloadProgress(_ release: ReleaseInfo, _ value: Double) {
        guard case .downloading = update, value - lastProgress >= 0.01 || value >= 1 else { return }
        lastProgress = value
        update = .downloading(release, value)
    }

    private func downloadFinished(_ release: ReleaseInfo, _ asset: ReleaseAsset, _ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            update = .failed("下载没有完成：\(error.localizedDescription)")
        case .success(let url):
            Task {
                if let expected = asset.sha256 {
                    let actual = await Task.detached(operation: { try? UpdateCheck.sha256(of: url) }).value
                    guard actual == expected else {
                        try? FileManager.default.removeItem(at: url)
                        update = .failed("下载的安装包校验不对，已经删掉。请稍后再试。")
                        return
                    }
                }
                update = .installing(release)
                NSWorkspace.shared.open(url)
                waitForInstall(release)
            }
        }
    }

    /// 安装器装完后，“应用程序”里的版本号会变；那时退出并打开新版本。
    private func waitForInstall(_ release: ReleaseInfo) {
        pollTask?.cancel()
        pollTask = Task {
            for _ in 0..<900 {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                if let installed = Installation.installedVersion(), !AppVersion.isNewer(release.version, than: installed) {
                    saveNow()
                    Installation.relaunch(Installation.applicationsURL)
                    return
                }
            }
            update = .available(release)
        }
    }

    // MARK: 安装位置和卸载

    func moveToApplications() {
        guard !moving else { return }
        moving = true
        saveNow()
        Task {
            let result = await Task.detached(operation: { Installation.copyToApplications() }).value
            moving = false
            switch result {
            case .success(let url):
                Installation.relaunch(url)
            case .failure(let error):
                if error != .cancelled { message = Message(tone: .error, text: "没有放进“应用程序”：\(error.message)") }
            }
        }
    }

    func uninstall() {
        let alert = NSAlert()
        alert.messageText = "卸载充电上限？"
        alert.informativeText = "会关掉登录启动，删掉这台 Mac 上的配置，并把 MacBatteryCharge 移到废纸篓。充电上限和低电量模式保持现在的值。"
        alert.addButton(withTitle: "卸载")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        timer?.cancel()
        saveTask?.cancel()
        Task {
            let result = await Task.detached(operation: { Installation.uninstall() }).value
            switch result {
            case .success:
                NSApp.terminate(nil)
            case .failure(let error):
                message = Message(tone: .error, text: "没有卸载完：\(error.message)")
            }
        }
    }

    // MARK: 文字

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func clock(_ date: Date) -> String {
        ClockTime(minuteOfDay: currentMinute(date)).text
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(1, minutes)) 分钟" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分"
    }

    var menuTop: String { battery.present ? "\(decision.limit)%" : "—" }
    var menuBottom: String { battery.flow.menuWord }

    var statusTitle: String {
        let battery = battery
        guard battery.present else { return "没有电池" }
        switch battery.flow {
        case .charging: return "正在充电"
        case .discharging: return battery.externalConnected ? "接着电源也在放电" : "用电池"
        case .plugged:
            if let percent = battery.percent, percent >= decision.limit - 1 { return "停在上限" }
            return "电源接通"
        case .battery: return "用电池"
        case .noBattery: return "没有电池"
        }
    }

    var statusDetail: String {
        let battery = battery
        var parts: [String] = []
        if let minutes = battery.minutesToFull, battery.flow == .charging {
            parts.append("约 \(Self.duration(minutes)) 充满")
        } else if let minutes = battery.minutesToEmpty {
            parts.append("还能用约 \(Self.duration(minutes))")
        }
        if let watts = battery.watts, abs(watts) >= 0.5 {
            parts.append(String(format: watts > 0 ? "充入 %.1f W" : "放出 %.1f W", abs(watts)))
        }
        if parts.isEmpty { return battery.flow.sentence }
        return parts.joined(separator: " · ")
    }

    var limitLine: String {
        var text = "上限 \(decision.limit)%"
        switch decision.reason {
        case .schedule, .gap:
            if let change = schedule.nextChange(after: minute) {
                text += " · \(change.at.text) 起 \(change.limit)%"
            }
        case .topUp:
            if let until = topUpUntil { text += " · 临时充满到 \(Self.clock(until))" }
        case .deadline:
            text += " · 为 \(settings.deadline.text) 断电提前放开"
        case .heat:
            text += " · 过热保护"
        }
        return text
    }

    var tonight: Tonight? {
        let battery = battery
        guard battery.present, settings.deadlineEnabled, let percent = battery.percent else { return nil }
        let deadline = settings.deadline
        guard let plan = ChargePlanner.plan(schedule: schedule, minute: minute, percent: percent,
                                            deadline: deadline, rate: learnedRate, window: 1439) else { return nil }
        let title = "\(deadline.text) 断电"
        let speed = plan.learned
            ? String(format: "按这台机器学到的速度，每小时约 %.0f%%。", plan.rate * 60)
            : "按默认速度估算，用得越久越准。"
        if percent >= plan.target {
            return Tonight(title: title, detail: "已经 \(percent)%，断电时满电出门。", symbol: "checkmark.circle.fill", tone: .success)
        }
        if deadlineLift != nil {
            let eta = Date().addingTimeInterval(Double(plan.minutesNeeded) * 60)
            return Tonight(title: title, detail: "已提前放开到 \(plan.target)%，预计 \(Self.clock(eta)) 充满。" + speed,
                           symbol: "bolt.badge.clock.fill", tone: .info)
        }
        if !battery.externalConnected && plan.minutesToDeadline < 180 {
            return Tonight(title: title, detail: "现在用电池。断电前接上电源，会充到 \(plan.target)%。",
                           symbol: "powerplug", tone: .info)
        }
        let eta = Date().addingTimeInterval(Double(plan.etaMinutes) * 60)
        if plan.reachesInTime {
            return Tonight(title: title, detail: "预计 \(Self.clock(eta)) 到 \(plan.target)%，比断电早 \(Self.duration(plan.minutesToDeadline - plan.etaMinutes))。" + speed,
                           symbol: "moon.stars.fill", tone: .info)
        }
        return Tonight(title: title, detail: "按现在的速度来不及充到 \(plan.target)%。可以点「临时充满」先放开。" + speed,
                       symbol: "exclamationmark.triangle.fill", tone: .error)
    }

    private func notify(_ id: String, _ title: String, _ body: String) {
        guard settings.notifications, !preview else { return }
        Notifier.post(id: id, title: title, body: body)
    }

    // MARK: 截图用

    func loadPreview(_ value: SystemReading, history: ChargeHistory, minute: Int) {
        reading = value
        self.history = history
        self.minute = minute
        recompute()
    }
}
