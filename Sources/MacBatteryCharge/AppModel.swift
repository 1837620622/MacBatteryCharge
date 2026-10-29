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

    /// 所有给用户看的错误同时写进本机日志，方便出问题时带日志提 issue。
    private func fail(_ text: String) {
        Log.write("error", text)
        message = Message(tone: .error, text: text)
    }

    @Published private(set) var reading: SystemReading?
    @Published private(set) var history = ChargeHistory()
    /// 长期记录：一天一行，用来学作息、给温馨提醒。和 72 小时的曲线分开存。
    @Published private(set) var journal = HabitJournal()
    /// 从长期记录里读出来的几句话。记录不够时是空的。
    @Published private(set) var tips: [HabitTip] = []
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
    /// 放电帮手的最新状态。nil 表示没装或连不上。
    @Published private(set) var helper: HelperStatus?
    @Published private(set) var helperBusy = false
    @Published private(set) var discharging = false
    /// 窗口真的看得见时为 true（没被盖住、没最小化）。看得见时每 2 秒读一次，动画也只在这时跑。
    @Published var windowVisible = false {
        didSet { if windowVisible != oldValue { pollingModeChanged() } }
    }
    /// 刘海灵动岛展开时也要实时。
    var islandOpen = false {
        didSet { if islandOpen != oldValue { pollingModeChanged() } }
    }
    @Published private(set) var forecast: [ForecastPoint] = []

    /// 菜单栏要跟着变。
    var onStatusChange: (() -> Void)?
    /// 插上或拔掉电源时，刘海灵动岛弹一下。
    var onPlugChange: ((Bool) -> Void)?
    let preview: Bool

    private var lastValidIntervals: [Interval]
    private var timer: Task<Void, Never>?
    private var updateTimer: Task<Void, Never>?
    /// 「应用程序」里装好的版本，第一次看到时记下来；下一次还是它，才说明安装包已经装完。
    private var settledVersion: String?
    private var refreshing = false
    private var refreshStartedAt: Date?
    private var writingSince = Date.distantPast
    private var forecastAt = Date.distantPast
    private var refreshAgain = false
    private var writingLimit = false
    private var failedWrite: (limit: Int, at: Date)?
    private var saveTask: Task<Void, Never>?
    private var lastFlow: PowerFlow?
    private var wasExternal = false
    private var lastHistorySave = Date.distantPast
    private var lastJournalDay: String?
    /// 上一次写进长期记录的样本，用来算插拔和时长。
    private var journalPrevious: ChargeSample?
    private var pollTask: Task<Void, Never>?
    private var syncingHelper = false
    private var lastSentLimit: Int?
    private var lastHelperSend = Date.distantPast

    init(preview: Bool = false, previewMode: ChargeMode? = nil, previewLanguage: AppLanguage? = nil) {
        self.preview = preview
        let loaded = preview ? AppSettings() : AppSettings.load()
        var start = loaded
        // 只给截图用：不写回设置文件。
        if let previewMode { start.mode = previewMode }
        if let previewLanguage { start.language = previewLanguage }
        // 界面语言在画出第一个字之前就要定下来，否则会先闪一下中文。
        Lang.current = start.language
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
            journal = HabitJournal.load(from: AppSettings.journalURL)
            tips = HabitTips.items(journal: journal)
            journalPrevious = history.samples.last
        }
        recompute()
    }

    // MARK: 读数

    var battery: BatterySnapshot { reading?.battery ?? BatterySnapshot() }
    var currentInterval: Interval? { schedule.interval(at: minute) }
    var currentIndex: Int? { schedule.index(at: minute) }
    /// 系统上限和这一段的计划不一致。分两种：正在改（短暂），和改失败（要提示）。
    var systemLimitMismatch: Bool {
        guard let value = reading?.chargeLimit.value else { return false }
        return value != decision.limit
    }

    /// 上一次写上限失败了，而且还没有到可以重试的时候。
    var limitWriteFailed: Bool {
        guard let failed = failedWrite, failed.limit == decision.limit else { return false }
        return Date().timeIntervalSince(failed.at) < 300
    }

    var advice: [AdviceItem] {
        Advice.top(Advice.items(battery: battery, memory: reading?.memory ?? MemorySnapshot(),
                                limit: reading?.chargeLimit.isSupported == true || helperUsable ? decision.limit : nil,
                                heatActive: heatActive, discharging: discharging))
    }

    var learnedRate: Double? { history.learnedRate() }
    /// 从历史里学到的拔电源时间，智能模式用。
    /// 学到的「平时几点拔电源」。关掉学习、或者记录还不够，就是 nil。
    var learnedUnplug: ClockTime? { settings.learnHabits ? journal.learnedUnplug() : nil }
    /// 备电要按的离电时间。智能模式先用学到的；没学会，或者是别的模式，就用自己设的那个（开着才有）。
    var departureTime: ClockTime? {
        if settings.mode == .smart, let learned = learnedUnplug { return learned }
        return settings.deadlineEnabled ? settings.deadline : nil
    }
    /// 智能模式这一轮算出来的结果，界面用它说人话。
    private(set) var smartDecision: SmartDecision?

    /// 现在这套模式实际要的上限和原因。
    var modeDescription: String {
        switch settings.mode {
        case .smart:
            guard let smart = smartDecision else { return settings.mode.title }
            return SmartPolicy.explain(smart, target: settings.unplugTarget)
        case .fixed:
            return T("按时间表 · %@%", ["\(decision.limit)"])
        case .full:
            return T("一直充到 100%")
        }
    }

    /// 帮手断开了电源适配器：系统会说没接电源，但其实线还插着。
    var adapterCut: Bool { helper?.adapterEnabled == false }
    /// 上次帮手说电源是断开的。帮手没响应时它不会自己变回来，所以卸载前要靠它判断。
    var adapterMayBeCut = false
    var displayFlow: PowerFlow { discharging ? .discharging : battery.flow }
    /// 画面里的动画只在窗口看得见、并且没开“减少动态效果”时才跑。
    var liveMotion: Bool { windowVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var now: Date { reading?.date ?? Date() }

    // MARK: 生命周期

    func start() {
        guard !preview, timer == nil else { return }
        refresh()
        timer = makeTimer()
        updateTimer = makeUpdateTimer()
    }

    /// 启动十秒后查一次更新。之后每分钟看一眼「应用程序」里装好的版本（你手动装上以后，旧版本会自己重新打开），每小时查一次更新。
    private func makeUpdateTimer() -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            var minutes = 0
            while !Task.isCancelled {
                self?.watchInstalledVersion()
                if minutes % 60 == 0 { self?.maybeCheckForUpdates() }
                minutes += 1
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var pollSeconds: Double { windowVisible || islandOpen ? 2 : 30 }

    private func makeTimer() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollSeconds ?? 30))
                if Task.isCancelled { return }
                self?.refresh()
            }
        }
    }

    /// 窗口出现或消失、灵动岛展开或收起：换一个读数的节奏，马上读一次。
    private func pollingModeChanged() {
        guard !preview, timer != nil else { return }
        timer?.cancel()
        timer = makeTimer()
        if windowVisible || islandOpen { refresh() }
    }

    func refresh() {
        guard !preview else { return }
        // 读数超过 30 秒还没回来，就当它卡住了，再读一次，免得一卡住界面就再也不动。
        if refreshing, let started = refreshStartedAt, Date().timeIntervalSince(started) < 30 {
            refreshAgain = true
            return
        }
        refreshing = true
        refreshStartedAt = Date()
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
        // 帮手断开电源适配器放电时，系统会说“没接电源”，这里仍然算接着。
        let external = battery.externalConnected || value.helper?.adapterEnabled == false

        heatActive = ChargePolicy.heatActive(previous: heatActive, celsius: battery.celsius, external: external)

        if wasExternal != external && reading != nil && lastFlow != nil { onPlugChange?(external) }
        // 临时充满和提前放开都在拔掉电源时结束。
        if wasExternal && !external {
            topUpUntil = nil
            deadlineLift = nil
        }
        wasExternal = external
        if let until = topUpUntil, value.date >= until { topUpUntil = nil }
        if let lift = deadlineLift, value.date >= lift.until || !settings.deadlineEnabled || settings.mode != .fixed {
            deadlineLift = nil
        }

        // 断电前放开只属于固定模式。智能模式自己算备电时间，不在这里另起一套，也就不会发错通知。
        if settings.mode == .fixed, settings.deadlineEnabled, external, deadlineLift == nil, let percent = battery.percent,
           let plan = ChargePlanner.plan(schedule: schedule, minute: minute, percent: percent,
                                         deadline: settings.deadline, target: settings.unplugTarget,
                                         rate: learnedRate), plan.liftNow {
            deadlineLift = (plan.target, value.date.addingTimeInterval(Double(plan.minutesToDeadline) * 60))
            notify("deadline", T("提前放开到 %@%", ["\(plan.target)"]), T("按这台机器的充电速度，赶在 %@ 断电前充满。", ["\(settings.deadline.display)"]))
        }

        helper = value.helper
        // 帮手没响应时 value.helper 是 nil，这里保持上次的判断，不把“断开”的状态忘掉。
        if let status = value.helper { adapterMayBeCut = status.adapterEnabled == false }
        let previousHeat = decision.reason == .heat
        recompute()
        updateDischarge()
        recomputeForecast()
        if decision.reason == .heat && !previousHeat {
            notify("heat", T("电池偏热，先停在 80%"), T("降到 33°C 以下再按时间表继续。"))
        }

        let flow = battery.flow
        if lastFlow == .charging && flow == .plugged, let percent = battery.percent, percent >= decision.limit - 1 {
            notify("limit", T("已停在 %@%", ["\(percent)"]), T("电源直接供电，电池不再往上充。"))
        }
        lastFlow = flow

        record(value)
        autoApplyLimit()
        syncHelper()
        onStatusChange?()
        if refreshAgain {
            refreshAgain = false
            refresh()
        }
    }

    private func recompute() {
        switch settings.mode {
        case .smart:
            let input = SmartInput(percent: battery.percent, external: battery.externalConnected || adapterCut,
                                   minute: minute, dailyCap: settings.smartDailyCap,
                                   unplugTarget: settings.unplugTarget,
                                   deadline: settings.deadlineEnabled ? settings.deadline : nil,
                                   learnedUnplug: learnedUnplug, rate: learnedRate,
                                   heat: heatActive, topUp: topUpUntil != nil)
            let smart = SmartPolicy.decide(input)
            smartDecision = smart
            decision = smart.decision
        case .fixed:
            smartDecision = nil
            decision = ChargePolicy.decide(schedule: schedule, minute: minute, topUp: topUpUntil != nil,
                                           deadlineLift: deadlineLift?.target, heat: heatActive)
        case .full:
            smartDecision = nil
            decision = ChargePolicy.applyHeat(LimitDecision(limit: 100, reason: .full, scheduled: 100), heat: heatActive)
        }
    }

    private func record(_ value: SystemReading) {
        guard let percent = value.battery.percent, value.battery.present else { return }
        let sample = ChargeSample(t: value.date, p: percent, c: value.battery.flow == .charging,
                                  x: value.battery.externalConnected, l: decision.limit)
        history.add(sample)
        // 长期记录按「天」累加。帮手断开电源时系统说没接电源，这里按真实状态记，
        // 否则一边接电源放电的日子会被记成整天用电池。
        var journalSample = sample
        journalSample.x = value.battery.externalConnected || value.helper?.adapterEnabled == false
        journal.absorb(journalSample, previous: journalPrevious, day: Self.dayKey(value.date),
                       celsius: value.battery.celsius, cycles: value.battery.cycles, health: value.battery.health)
        journalPrevious = journalSample
        if let health = value.battery.health {
            history.addHealth(HealthPoint(day: Self.dayFormatter.string(from: value.date), health: health, cycles: value.battery.cycles))
        }
        let day = Self.dayKey(value.date)
        if value.date.timeIntervalSince(lastHistorySave) >= 240 || lastJournalDay != day {
            lastHistorySave = value.date
            lastJournalDay = day
            let copy = history
            let journalCopy = journal
            Task.detached(priority: .background) {
                try? copy.save(to: AppSettings.historyURL)
                try? journalCopy.save(to: AppSettings.journalURL)
            }
            refreshTips()
        }
    }

    /// 从长期记录里重算那几句话。记录变了才重算。
    private func refreshTips() {
        let next = HabitTips.items(journal: journal)
        if next != tips { tips = next }
    }

    /// 换段、临时充满、提前放开、过热保护都在这里写给系统。不要密码。
    /// 系统设置里被改过也会改回时间表的值。
    private func autoApplyLimit() {
        guard !preview, let current = reading?.chargeLimit.value, current != decision.limit else { return }
        if writingLimit, Date().timeIntervalSince(writingSince) < 30 { return }
        let limit = decision.limit
        if let failed = failedWrite, failed.limit == limit, Date().timeIntervalSince(failed.at) < 300 { return }
        writingLimit = true
        writingSince = Date()
        Task {
            let error = await Task.detached { ChargeBridge.write(limit) }.value
            writingLimit = false
            if let error {
                failedWrite = (limit, Date())
                fail(T("充电上限没写上：%@", ["\(error)"]))
            } else {
                failedWrite = nil
            }
            refresh()
        }
    }

    // MARK: 放电帮手

    var helperUsable: Bool { helper?.adapterControl == true && !helperOutdated }

    var helperOutdated: Bool {
        guard let helper else { return false }
        return helper.protocolVersion != HelperInfo.protocolVersion || helper.version != Installation.version
    }

    /// Apple 芯片和 Intel 的安装包各带一份对应的帮手。
    var helperInstallable: Bool { HelperInstaller.bundledBinary != nil }

    /// 这一段开着放电，但帮手没装好。
    var dischargeWantedButMissing: Bool {
        settings.mode.allowsDischarge && battery.present && schedule.discharge(at: minute) && !helperUsable
    }

    /// 系统没有原生充电上限时（旧系统、Intel），上限交给帮手：直接停充，或者写 Intel 的 BCLM。
    private var helperHandlesLimit: Bool {
        guard let helper, !helperOutdated else { return false }
        guard helper.chargeControl == .direct || helper.chargeControl == .intelCeiling else { return false }
        return reading?.chargeLimit.isSupported != true
    }

    /// 这一台的充电上限现在谁都管不了：系统那边没有接口，帮手也说自己不碰。
    /// 这时候不能装作在护电池，界面要直说。
    var limitUnenforceable: Bool {
        guard !preview, battery.present else { return false }
        guard reading?.chargeLimit.isSupported != true else { return false }
        if helperHandlesLimit { return false }
        guard let helper, !helperOutdated else { return false }
        return helper.chargeControl == .system || helper.chargeControl == .none
    }

    /// 今天不放电：只管当天，过了午夜自动恢复。
    var dischargeOffToday: Bool { settings.dischargeOffDay == Self.dayKey(Date()) }

    func toggleDischargeOffToday() {
        settings.dischargeOffDay = dischargeOffToday ? nil : Self.dayKey(Date())
        updateDischarge()
        syncHelper()
        onStatusChange?()
    }

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

    private func updateDischarge() {
        // 只有固定模式能主动放电。智能模式的承诺是「随时有电」，一边接电源一边掉电和它冲突。
        guard settings.mode.allowsDischarge else {
            if discharging { discharging = false }
            return
        }
        let external = battery.externalConnected || helper?.adapterEnabled == false
        // 温度读不到就不放电（Calma 也是这样）：放电时电池会发热，看不见温度就不冒这个险。
        discharging = ChargePolicy.shouldDischarge(
            previous: discharging, percent: battery.percent, decision: decision,
            enabled: helperUsable && schedule.discharge(at: minute) && !dischargeOffToday && battery.celsius != nil,
            external: external, resumeAt: schedule.resumeAt(at: minute))
    }

    /// 把想要的状态告诉帮手。放电指令只有 2 分钟有效：放电时 20 秒续一次；平时每 5 分钟报一次到，
    /// 帮手才知道程序还在，原生以外的上限才会一直保留。
    private func syncHelper() {
        guard !preview, !syncingHelper, let current = helper, !helperOutdated else { return }
        let wantedLimit = helperHandlesLimit ? decision.limit : nil
        let wantedTarget = discharging ? decision.limit : nil
        let wantedResume = discharging ? schedule.resumeAt(at: minute) : nil
        let same = current.limit == wantedLimit && current.dischargeTo == wantedTarget
        let interval: TimeInterval = discharging ? 20 : 300
        if same, Date().timeIntervalSince(lastHelperSend) < interval { return }
        lastHelperSend = Date()
        syncingHelper = true
        lastSentLimit = wantedLimit
        Task {
            let request = HelperRequest(cmd: .apply, limit: wantedLimit, dischargeTo: wantedTarget, resumeAt: wantedResume, lease: 120)
            let status = await Task.detached { HelperClient.send(request) }.value
            syncingHelper = false
            if let status { helper = status }
        }
    }

    func installHelper() {
        guard !helperBusy, !preview else { return }
        helperBusy = true
        Task {
            let result = await Task.detached { HelperInstaller.install(version: Installation.version) }.value
            helperBusy = false
            switch result {
            case .ok:
                message = Message(tone: .success, text: T("放电帮手装好了。"))
            case .cancelled:
                message = Message(tone: .info, text: T("密码框取消了，放电帮手没有装。"))
            case .failed(let text):
                fail(T("放电帮手没有装好：%@", ["\(text)"]))
            }
            refresh()
        }
    }

    func removeHelper() {
        guard !helperBusy, !preview else { return }
        helperBusy = true
        let mayBeCut = adapterMayBeCut
        Task {
            let result = await Task.detached { HelperInstaller.uninstall(adapterMayBeCut: mayBeCut) }.value
            helperBusy = false
            discharging = false
            helper = nil
            if result == .ok { adapterMayBeCut = false }
            switch result {
            case .ok:
                message = Message(tone: .success, text: T("放电帮手已卸载，电源已接回。"))
            case .cancelled:
                message = Message(tone: .info, text: T("密码框取消了，放电帮手还在。"))
            case .failed(let text):
                fail(T("放电帮手没有卸载：%@", ["\(text)"]))
            }
            refresh()
        }
    }

    /// 退出时要把电源接回来。有帮手才需要等它。
    var needsHelperRelease: Bool { !preview && helper != nil }

    /// 程序退出时：电源接回来，充电上限不动。在后台做，调用的人最多等一秒多；帮手卡住也照样退出，
    /// 它的租约到期会自己接回电源。绝不在主线程上等它。
    func releaseHelperForQuit() async {
        let request = HelperRequest(cmd: .apply, limit: lastSentLimit, dischargeTo: nil)
        _ = await Task.detached(priority: .userInitiated) { HelperClient.send(request, timeout: 1) }.value
    }

    // MARK: 预测

    /// 预测每 30 秒算一次就够了，电量曲线不需要每 2 秒重算。
    private func recomputeForecast(force: Bool = false) {
        if !force, Date().timeIntervalSince(forecastAt) < 30 { return }
        forecastAt = Date()
        guard battery.present, let percent = battery.percent else {
            if !forecast.isEmpty { forecast = [] }
            return
        }
        forecast = Forecast.points(
            schedule: forecastSchedule, minute: minute, percent: percent,
            external: battery.externalConnected || adapterCut,
            deadline: departureTime,
            target: settings.unplugTarget,
            chargeRate: learnedRate,
            dischargeAvailable: settings.mode == .fixed && helperUsable && !dischargeOffToday,
            topUpMinutes: topUpUntil.map { max(0, Int($0.timeIntervalSince(now) / 60)) },
            horizon: 480)
    }

    /// 预测按的时间表。固定模式就是用户排的那张；智能模式是整天停在平时的上限；一直充满没有时间表，空档就是 100%。
    private var forecastSchedule: Schedule {
        switch settings.mode {
        case .fixed: return schedule
        case .smart: return SmartPolicy.flatSchedule(cap: SmartPolicy.clampDailyCap(settings.smartDailyCap))
        case .full: return .empty
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
        if settings.deadlineEnabled != old.deadlineEnabled || settings.deadline != old.deadline
            || settings.unplugTarget != old.unplugTarget || settings.mode != old.mode { deadlineLift = nil }
        // 临时充满的结束时间是按模式定的，换了模式就重新来。
        if settings.mode != old.mode { topUpUntil = nil }
        if settings.language != old.language {
            Lang.current = settings.language
            // 菜单栏、窗口标题这些不在 SwiftUI 里的字要自己重画一遍。
            onStatusChange?()
        }
        if settings.launchAtLogin != old.launchAtLogin { syncLogin() }
        if settings.notifications && !old.notifications {
            Notifier.requestAuthorization { granted in
                Task { @MainActor in
                    if !granted {
                        self.settings.notifications = false
                        self.message = Message(tone: .info, text: T("通知没有打开。可以在系统设置的“通知”里允许充电上限。"))
                    }
                }
            }
        }
        recompute()
        recomputeForecast(force: true)
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
            fail(T("设置没有存上：%@", ["\(error.localizedDescription)"]))
        }
    }

    /// 登录项要跟开关对上。系统的登录项服务会回话，可能慢，所以放到后台做，回来再改界面。
    func syncLogin() {
        guard !preview else { return }
        let enabled = settings.launchAtLogin
        Task.detached(priority: .utility) {
            let note = LoginItem.sync(enabled: enabled)
            let state = LoginItem.state
            await MainActor.run {
                self.loginNote = note
                self.loginState = state
            }
        }
    }

    func refreshLoginState() {
        guard !preview else { return }
        Task.detached(priority: .utility) {
            let state = LoginItem.state
            await MainActor.run {
                self.loginState = state
                if state == .on || !self.settings.launchAtLogin { self.loginNote = nil }
            }
        }
    }

    // MARK: 时间表编辑

    var canAddInterval: Bool {
        settings.intervals.count < Schedule.maxIntervals && scheduleError == nil
            && Schedule.firstFreeSlot(in: settings.intervals) != nil
    }

    var addHint: String? {
        if settings.intervals.count >= Schedule.maxIntervals { return T("最多 %@ 段", ["\(Schedule.maxIntervals)"]) }
        if scheduleError != nil { return T("先改好上面的问题") }
        if Schedule.firstFreeSlot(in: settings.intervals) == nil { return T("一天已经排满，先缩短一段再加") }
        return nil
    }

    func addInterval() {
        guard canAddInterval, let slot = Schedule.firstFreeSlot(in: settings.intervals) else { return }
        // 默认停在 80%：加段多半是为了少满电，设成 100% 就和空档一样，看不出加了什么。
        let item = Interval(start: slot.start, end: slot.end, limit: 80)
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

    /// 一直充满本来就是 100%，不需要临时充满。
    var topUpAvailable: Bool { battery.present && settings.mode != .full }

    func toggleTopUp() {
        guard topUpAvailable || topUpUntil != nil else { return }
        if topUpUntil != nil {
            topUpUntil = nil
        } else if settings.mode == .fixed {
            // 固定模式：充到这一段结束，也就是下一段开始或拔掉电源。
            let ahead = schedule.minutesUntilBoundary(from: minute) ?? 1440
            topUpUntil = Date().addingTimeInterval(Double(ahead) * 60)
        } else {
            // 智能没有时间段可以停，所以一直到拔掉电源为止。
            topUpUntil = Date.distantFuture
        }
        recompute()
        recomputeForecast(force: true)
        onStatusChange?()
        autoApplyLimit()
    }

    // MARK: 立即应用

    /// 平时上限自动写，不用点。这里给一个「马上写一次」，不要密码。
    func applyNow() {
        guard !preview else { return }
        if let error = scheduleError {
            fail(T("%@。改好之后再应用。", ["\(error.message)"]))
            return
        }
        failedWrite = nil
        autoApplyLimit()
        message = Message(tone: .info, text: T("上限现在是 %@%", ["\(decision.limit)"]))
    }

    // MARK: 习惯

    /// 已经记下几次「离开电源」。学习至少要 3 次。
    var learnedCount: Int { journal.unplugMinutes.count }

    /// 清掉学到的作息，从头学。电量记录和温度记录不动。
    func forgetHabits() {
        journal.forgetHabits()
        let copy = journal
        Task.detached(priority: .background) { try? copy.save(to: AppSettings.journalURL) }
        refreshTips()
        recompute()
        recomputeForecast(force: true)
        onStatusChange?()
        autoApplyLimit()
    }

    // MARK: 检查更新

    /// 启动十秒后查一次，之后每 6 小时在后台查一次。查到新版本就提示你：窗口最上面和设置里各有一条。
    /// 下载和安装都由你来：点「下载新版本」，在浏览器里下对应芯片的安装包，打开它就能装。软件不替你下、不替你装，也不要密码。
    func maybeCheckForUpdates() {
        guard !preview, settings.autoCheckUpdates else { return }
        if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < 6 * 3600 { return }
        checkForUpdates(userInitiated: false)
    }

    /// 「立即检查」和自动检查都走这里。正在重新打开的时候，不动界面。
    func checkForUpdates(userInitiated: Bool) {
        guard !preview else { return }
        if case .relaunching = update { return }
        if userInitiated { update = .checking }
        Task {
            do {
                let release = try await UpdateCheck.fetchLatest()
                settings.lastUpdateCheck = Date()
                if AppVersion.isNewer(release.version, than: Installation.version) {
                    // 自动检查时，点过「以后再说」的版本不再提示；手动检查照样显示。
                    if userInitiated || settings.skippedVersion != release.version {
                        update = .available(release)
                    } else {
                        update = .idle
                    }
                } else {
                    update = userInitiated ? .upToDate : .idle
                }
            } catch {
                update = userInitiated ? .failed(T("查不到新版本：%@", ["\(error.localizedDescription)"])) : .idle
            }
        }
    }

    /// 「下载新版本」：在浏览器里下对应芯片的安装包。找不到安装包时，去发布页。
    func openDownload(_ release: ReleaseInfo) {
        NSWorkspace.shared.open(release.package(arm64: UpdateCheck.isArm64)?.url ?? release.page ?? UpdateCheck.releasesPage)
    }

    /// 去发布页看说明、手动下。
    func openDownloadPage() {
        NSWorkspace.shared.open(UpdateCheck.releasesPage)
    }

    /// 「以后再说」：这一版不再提示，下一版出来照样提示。
    func dismissUpdate(_ release: ReleaseInfo) {
        settings.skippedVersion = release.version
        update = .idle
    }

    /// 你手动装上新版本以后，正在跑的旧版本要自己重新打开，不用重启电脑。
    /// 每分钟看一眼「应用程序」里装的版本；同一个版本连续两次都看到，才说明安装包已经装完。
    private func watchInstalledVersion() {
        guard !preview, Installation.isInApplications,
              let installed = Installation.installedVersion(),
              AppVersion.isNewer(installed, than: Installation.version) else {
            settledVersion = nil
            return
        }
        guard settledVersion == installed else {
            settledVersion = installed
            return
        }
        update = .relaunching(installed)
        Installation.relaunchAfterExit(background: !windowVisible)
        NSApp.terminate(nil)
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

    // MARK: 安装位置和卸载

    func moveToApplications() {
        guard !moving else { return }
        moving = true
        saveNow()
        Task {
            let result = await Task.detached(operation: { Installation.copyToApplications() }).value
            moving = false
            switch result {
            case .success:
                Installation.relaunchAfterExit(background: false)
                NSApp.terminate(nil)
            case .failure(let error):
                if error != .cancelled { fail(T("没有放进“应用程序”：%@", ["\(error.message)"])) }
            }
        }
    }

    /// 打开设置和数据所在的地方，卸载前想自己看一眼或者备份用。
    func openDataFolder() {
        let url = AppSettings.directory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: 反馈

    /// 「反馈问题」：打开 GitHub 新建 issue，标题和诊断信息预填好。诊断只有这台机器的读数、上限谁在管、
    /// 帮手和更新的状态，以及最近的日志（用户主目录已经换成 ~）。没有账号，也没有窗口里的内容。
    /// 正文太长放不进网址，就复制到剪贴板、打开空的页面，并且说清楚，绝不悄悄丢掉。
    func sendFeedback() {
        let body = feedbackBody()
        var items = [URLQueryItem(name: "title", value: T("问题反馈（%@）", ["\(Installation.version)"]))]
        if body.utf8.count <= 6000 {
            items.append(URLQueryItem(name: "body", value: body))
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
            message = Message(tone: .info, text: T("诊断信息太长，放不进网址。已经复制到剪贴板，在打开的页面里粘贴到正文就行。"))
        }
        var components = URLComponents(url: AppInfo.newIssuePage, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }

    /// 诊断正文：这台机器的读数，加上最近 120 行日志。
    private func feedbackBody() -> String {
        var lines = [
            "版本：\(Installation.version)（\(UpdateCheck.isArm64 ? "Apple 芯片" : "Intel")）",
            "系统：\(ProcessInfo.processInfo.operatingSystemVersionString)",
            "上限执行者：\(limitOwner)",
            "模式：\(settings.mode)",
            "电量：\(battery.percent.map { "\($0)%" } ?? "读不到")",
            "放电帮手：\(helperUsable ? (helperOutdated ? "装了，但是旧版本" : "已装") : "没装")",
            "更新状态：\(String(describing: update))",
            "",
            "最近的日志：",
        ]
        lines += Log.recentLines(120).map(Log.redact)
        return lines.joined(separator: "\n")
    }

    // MARK: 文字

    /// 出问题时复制给开发者。只有这台机器的读数和帮手状态，没有账号和个人信息。
    /// 诊断里写清楚这一台的上限到底是谁在管，免得用户以为软件在护电池。
    private var limitOwner: String {
        if reading?.chargeLimit.isSupported == true { return T("系统") }
        if helperHandlesLimit { return T("帮手") }
        if let helper, helper.chargeControl == .system { return T("系统（新固件，帮手不碰）") }
        return T("没有人")
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func clock(_ date: Date) -> String {
        ClockTime(minuteOfDay: currentMinute(date)).display
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return T("%@ 分钟", ["\(max(1, minutes))"]) }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? T("%@ 小时", ["\(hours)"]) : T("%@ 小时 %@ 分", ["\(hours)", "\(rest)"])
    }

    /// 菜单栏上显示实际生效的上限。写失败了就显示系统现在的值，不能拿目标值糊过去。
    var menuTop: String {
        guard battery.present else { return "—" }
        if limitWriteFailed, let actual = reading?.chargeLimit.value { return "\(actual)%" }
        return "\(decision.limit)%"
    }
    var menuBottom: String { discharging ? T("放电") : battery.flow.menuWord }

    var statusTitle: String {
        let battery = battery
        guard battery.present else { return T("没有电池") }
        if discharging { return T("放电中") }
        switch battery.flow {
        case .charging: return T("充电中")
        case .discharging: return battery.externalConnected ? T("电源不够用") : T("用电池")
        case .plugged:
            if let percent = battery.percent, percent >= decision.limit - 1 { return T("已停住") }
            return T("电源接通")
        case .battery: return T("用电池")
        case .noBattery: return T("没有电池")
        }
    }

    var statusDetail: String {
        let battery = battery
        if discharging { return T("放到 %@% 停，再由电源供电", ["\(decision.limit)"]) }
        var parts: [String] = []
        if let minutes = battery.minutesToFull, battery.flow == .charging {
            parts.append(T("约 %@ 充满", ["\(Self.duration(minutes))"]))
        } else if let minutes = battery.minutesToEmpty {
            parts.append(T("还能用约 %@", ["\(Self.duration(minutes))"]))
        }
        if parts.isEmpty { return battery.flow.sentence }
        return parts.joined(separator: " · ")
    }

    var limitLine: String {
        var text = T("停在 %@%", ["\(decision.limit)"])
        switch decision.reason {
        case .schedule, .gap:
            if discharging { text += T(" · 放电中") }
            if let change = schedule.nextChange(after: minute) {
                text += T(" · %@ 起 %@%", ["\(change.at.display)", "\(change.limit)"])
            }
        case .topUp:
            if let until = topUpUntil, until != Date.distantFuture {
                text += T(" · 临时充满到 %@", ["\(Self.clock(until))"])
            } else {
                text += T(" · 临时充满，拔掉电源时结束")
            }
        case .deadline:
            text += T(" · 提前开始补")
        case .heat:
            text += T(" · 过热保护")
        case .smart:
            break
        case .full:
            text += T(" · 一直充满")
        }
        return text
    }

    var tonight: Tonight? {
        let battery = battery
        guard battery.present, let percent = battery.percent, let deadline = departureTime else { return nil }
        let plan: ChargePlan?
        switch settings.mode {
        case .smart:
            plan = ChargePlanner.plan(minute: minute, percent: percent, deadline: deadline,
                                      target: settings.unplugTarget, base: settings.smartDailyCap,
                                      rate: learnedRate, window: 1439)
        case .fixed:
            plan = ChargePlanner.plan(schedule: schedule, minute: minute, percent: percent,
                                      deadline: deadline, target: settings.unplugTarget,
                                      rate: learnedRate, window: 1439)
        case .full:
            // 一直充满不看时间表，按现在就充来算。base 是 100，所以不会有放开时间。
            plan = ChargePlanner.plan(minute: minute, percent: percent, deadline: deadline,
                                      target: settings.unplugTarget, base: 100,
                                      rate: learnedRate, window: 1439)
        }
        guard let plan else { return nil }
        let title = T("%@ 左右拔电源 · 充到 %@%", ["\(deadline.display)", "\(plan.target)"])
        if percent >= plan.target {
            return Tonight(title: title, detail: T("现在 %@%，已经够了", ["\(percent)"]), symbol: "checkmark.circle.fill", tone: .success)
        }
        // 没接电源就没有确定的时间可给：只能说到时候要充多久，不能说几点能满。
        if !battery.externalConnected && !adapterCut {
            return Tonight(title: title,
                           detail: T("插上电源，约 %@ 就能充满", ["\(Self.duration(plan.minutesNeeded))"]),
                           symbol: "powerplug", tone: .info)
        }
        if deadlineLift != nil {
            let eta = now.addingTimeInterval(Double(plan.minutesNeeded) * 60)
            return Tonight(title: title, detail: T("已经开始补，预计 %@ 充满", ["\(Self.clock(eta))"]),
                           symbol: "bolt.badge.clock.fill", tone: .info)
        }
        let eta = now.addingTimeInterval(Double(plan.etaMinutes) * 60)
        if plan.reachesInTime {
            return Tonight(title: title, detail: T("约 %@ 充满，比拔电源早 %@",["\(Self.clock(eta))", "\(Self.duration(plan.minutesToDeadline - plan.etaMinutes))"]),
                           symbol: "moon.stars.fill", tone: .info)
        }
        return Tonight(title: title, detail: T("来不及充到 %@%，可以点「临时充满」", ["\(plan.target)"]), symbol: "exclamationmark.triangle.fill", tone: .error)
    }

    private func notify(_ id: String, _ title: String, _ body: String) {
        guard settings.notifications, !preview else { return }
        Notifier.post(id: id, title: title, body: body)
    }

    // MARK: 截图用

    /// 截图用：直接放一个更新状态上去，不查网络。
    func loadPreviewUpdate(_ state: UpdateState) {
        update = state
    }

    func loadPreview(_ value: SystemReading, history: ChargeHistory, minute: Int) {
        reading = value
        helper = value.helper
        self.history = history
        self.minute = minute
        journal = HabitJournal()
        let calendar = Calendar.current
        for day in 0..<14 {
            guard let date = calendar.date(byAdding: .day, value: -day, to: value.date) else { continue }
            var record = DayRecord(day: Self.dayKey(date))
            record.lo = 42 + day % 5
            record.hi = day % 3 == 0 ? 100 : 80
            record.batteryMinutes = Double(200 + day * 7)
            record.powerMinutes = Double(900 - day * 5)
            record.fullMinutes = day % 3 == 0 ? 520 : 40
            record.unplug = 18 * 60 + 40 + day % 12
            record.plug = 9 * 60 + 5
            record.hottest = 33.5 + Double(day % 4)
            record.celsiusSum = 30 * Double(12 + day % 3)
            record.celsiusCount = 12
            record.cycles = 200 + day
            record.health = 93 - day / 20
            journal.days.append(record)
        }
        journal.days.reverse()
        journal.unplugMinutes = (0..<14).map { 18 * 60 + 40 + $0 % 12 }
        journal.plugMinutes = (0..<14).map { _ in 9 * 60 + 5 }
        tips = HabitTips.items(journal: journal)
        recompute()
        recomputeForecast(force: true)
    }
}
