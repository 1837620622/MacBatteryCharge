import SwiftUI
import Charts
import BatteryCore

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            if model.showGuide {
                GuideView(model: model).transition(.opacity)
            } else {
                MainView(model: model).transition(.opacity)
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
        .background(
            WindowBackdrop(look: model.settings.look, transparency: model.settings.transparency, preview: model.preview)
                .ignoresSafeArea()
        )
        .environment(\.windowLook, model.settings.look)
        .environment(\.isPreview, model.preview)
        .animation(.easeInOut(duration: 0.25), value: model.showGuide)
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @AppStorage("fold.top") private var topOpen = true
    @AppStorage("fold.bottom") private var bottomOpen = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                BannerStack(model: model)
                HeroCard(model: model)
                if let tonight = model.tonight { TonightRow(tonight: tonight) }

                FoldHeader(title: T("上排"), subtitle: T("读数"), summary: topSummary, open: $topOpen)
                if topOpen {
                    VStack(alignment: .leading, spacing: 12) {
                        ReadingsCard(model: model)
                        AdviceCard(items: model.advice)
                        HistoryCard(model: model)
                        JournalCard(model: model)
                    }
                    .transition(.opacity)
                }

                FoldHeader(title: T("下排"), subtitle: T("时间表和设置"), summary: bottomSummary, open: $bottomOpen)
                if bottomOpen {
                    VStack(alignment: .leading, spacing: 12) {
                        ModeCard(model: model)
                        ScheduleCard(model: model)
                        HelperCard(model: model)
                        LookCard(model: model)
                        LanguageCard(model: model)
                        SupportCard()
                        SystemCard(model: model)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { FooterBar(model: model) }
    }

    private var topSummary: String {
        let battery = model.battery
        guard battery.present else { return T("没有电池") }
        var parts = [battery.percent.map { "\($0)%" } ?? "—", battery.flow.menuWord]
        if let celsius = battery.celsius { parts.append(String(format: "%.0f°C", celsius)) }
        return parts.joined(separator: " · ")
    }

    private var bottomSummary: String {
        let count = model.settings.intervals.count
        var text = count == 0 ? T("全天 100%") : T("%@ 段", ["\(count)"])
        if model.settings.deadlineEnabled { text += T(" · %@ 断电", ["\(model.settings.deadline.text)"]) }
        return text
    }
}

// MARK: 折叠

/// 第一层：上排、下排。点一下整排收起，收起时右边写一句摘要。
struct FoldHeader: View {
    var title: String
    var subtitle: String
    var summary: String
    @Binding var open: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { open.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if !open {
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(title)，\(subtitle)")
        .accessibilityHint(open ? T("收起") : T("展开"))
    }
}

/// 第二层：卡片自己也能收起。收起状态记在本机。
struct FoldCard<Content: View>: View {
    var title: String
    var summary: String?
    @AppStorage private var open: Bool
    private let content: Content

    init(_ title: String, key: String, defaultOpen: Bool = true, summary: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        _open = AppStorage(wrappedValue: defaultOpen, "fold.\(key)")
        self.content = content()
    }

    var body: some View {
        Card {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    Spacer(minLength: 8)
                    if !open, let summary {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(open ? T("收起") : T("展开"))
            if open { content.transition(.opacity) }
        }
    }
}

// MARK: 顶部提示

struct BannerStack: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if !model.preview && Installation.shouldOfferMove {
            Banner(symbol: "folder.badge.plus", tint: .blue, title: T("放进“应用程序”"),
                   detail: T("登录自启和更新都在那里。")) {
                Button(model.moving ? T("正在放进去…") : T("放进去并重开")) { model.moveToApplications() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.moving)
            }
        }
        if model.dischargeWantedButMissing && model.helperInstallable && !model.preview {
            Banner(symbol: "arrow.down.to.line.compact", tint: .orange, title: T("这一段要放电"),
                   detail: T("装放电帮手后才能放到 %@%。装一次，要管理员密码。", ["\(model.decision.limit)"])) {
                Button(model.helperBusy ? T("正在安装…") : T("安装放电帮手")) { model.installHelper() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.helperBusy)
            }
        }
        if model.helperOutdated && !model.preview {
            Banner(symbol: "arrow.triangle.2.circlepath", tint: .orange, title: T("放电帮手要更新"),
                   detail: T("版本和软件对不上。更新要管理员密码。")) {
                Button(model.helperBusy ? T("正在更新…") : T("更新放电帮手")) { model.installHelper() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.helperBusy)
            }
        }
        if model.limitUnenforceable {
            Banner(symbol: "exclamationmark.triangle.fill", tint: .orange, title: T("这台 Mac 的上限没人执行"),
                   detail: T("系统没有充电上限接口，这台机器的固件又只能由系统自己管，所以 %@% 现在改不了。它仍然会按时提示你。", ["\(model.decision.limit)"])) {
                Link(T("说明"), destination: AppInfo.issuesPage)
            }
        }
        if let error = model.scheduleError {
            Banner(symbol: "exclamationmark.triangle.fill", tint: .red, title: T("时间表有问题"),
                   detail: error.message) { EmptyView() }
        }
        switch model.update {
        case .available(let release):
            Banner(symbol: "arrow.down.circle.fill", tint: .accentColor, title: T("有新版本 %@", ["\(release.version)"]),
                   detail: Self.firstNote(release.notes)) {
                Button(T("下载并安装")) { model.install(release) }
                    .buttonStyle(.borderedProminent)
                Button(T("跳过")) { model.skip(release) }
                if let page = release.page {
                    Link(T("说明"), destination: page)
                }
            }
        case .downloading(let release, let progress):
            Banner(symbol: "arrow.down.circle", tint: .accentColor, title: T("正在下载 %@", ["\(release.version)"]), detail: nil) {
                ProgressView(value: progress)
                    .frame(maxWidth: .infinity)
                Text("\(Int(progress * 100))%").monospacedDigit().foregroundStyle(.secondary)
            }
        case .installing:
            Banner(symbol: "shippingbox.fill", tint: .accentColor, title: T("安装器已打开"),
                   detail: T("装好后会自己重新打开。")) { EmptyView() }
        case .failed(let text):
            Banner(symbol: "exclamationmark.circle.fill", tint: .orange, title: T("更新没有完成"), detail: text) {
                Button(T("重试")) { model.checkForUpdates(userInitiated: true) }
            }
        default:
            EmptyView()
        }
    }

    /// 发布说明的第一行，太长就截断。
    static func firstNote(_ notes: String) -> String? {
        let line = notes.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#-* ")) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        return line.count > 42 ? String(line.prefix(42)) + "…" : line
    }
}

// MARK: 电量

struct HeroCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let battery = model.battery
        Card(padding: 14) {
            HStack(alignment: .center, spacing: 16) {
                DayDial(schedule: model.schedule, minute: model.minute, percent: battery.percent,
                        limit: model.decision.limit, flow: model.displayFlow, live: model.liveMotion,
                        selectedIndex: model.schedule.intervals.firstIndex { $0.id == model.editingID }) { index in
                    let id = model.schedule.intervals[index].id
                    withAnimation(.easeInOut(duration: 0.2)) { model.editingID = model.editingID == id ? nil : id }
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(model.statusTitle)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        if model.windowVisible { LiveDot(stamp: model.reading?.date) }
                    }
                    Text(model.statusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ReasonChip(text: model.limitLine, reason: model.decision.reason)
                }
            }
            Text(model.daySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if battery.present {
                FlowStrip(plugged: battery.externalConnected, adapterCut: model.adapterCut,
                          adapterWatts: battery.adapterWatts, batteryWatts: battery.watts, live: model.liveMotion)
                HStack(spacing: 8) {
                    Button {
                        model.toggleTopUp()
                    } label: {
                        Label(model.topUpActive ? T("结束临时充满") : T("临时充满"), systemImage: model.topUpActive ? "xmark.circle" : "bolt.fill")
                    }
                    .help(T("到下一段开始或拔掉电源前，先放开到 100%。"))
                    if model.helperUsable || model.dischargeOffToday {
                        Button {
                            model.toggleDischargeOffToday()
                        } label: {
                            Label(model.dischargeOffToday ? T("恢复今天放电") : T("今天不放电"), systemImage: "pause.circle")
                        }
                        .help(T("今天整天只保持现在的电量，过了午夜自动恢复。"))
                    }
                    if model.limitWriteFailed {
                        Text(T("没写上，等一会再试"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if model.systemLimitMismatch {
                        Text(T("正在改成 %@%", ["\(model.decision.limit)"]))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .controlSize(.small)
            }
        }
    }
}

struct ReasonChip: View {
    var text: String
    var reason: LimitReason

    private var tint: Color {
        switch reason {
        case .schedule: return .accentColor
        case .gap: return .secondary
        case .topUp: return .green
        case .deadline: return .indigo
        case .heat: return .orange
        case .smart: return .teal
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// 断电前的计划，一张两行的小卡。
struct TonightRow: View {
    var tonight: AppModel.Tonight

    private var tint: Color {
        switch tonight.tone {
        case .success: return .green
        case .info: return .indigo
        case .error: return .orange
        }
    }

    var body: some View {
        Card(padding: 10) {
            HStack(spacing: 10) {
                Image(systemName: tonight.symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tonight.title).font(.callout.weight(.semibold))
                    Text(tonight.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: 上排

struct ReadingsCard: View {
    @ObservedObject var model: AppModel

    private struct Item: Identifiable {
        var symbol: String
        var title: String
        var value: String
        var note: String?
        var tint: Color = .secondary
        var id: String { title }
    }

    private var items: [Item] {
        let battery = model.battery
        guard battery.present else {
            return [Item(symbol: "gauge.with.dots.needle.67percent", title: T("系统上限"), value: limitValue, note: limitNote)]
        }
        return [
            Item(symbol: "bolt", title: T("功率"), value: powerValue(battery), note: currentNote(battery),
                 tint: battery.flow == .charging ? .green : (battery.flow == .discharging ? .orange : .secondary)),
            Item(symbol: "thermometer.medium", title: T("温度"), value: battery.celsius.map { String(format: "%.1f°C", $0) } ?? "—",
                 note: thermalText, tint: (battery.celsius ?? 0) >= 40 ? .orange : .secondary),
            Item(symbol: "heart", title: T("健康"), value: battery.health.map { "\($0)%" } ?? "—", note: cycleNote(battery),
                 tint: (battery.health ?? 100) < 80 ? .orange : .secondary),
            Item(symbol: "powerplug", title: T("电源"), value: adapterValue(battery), note: model.adapterCut ? T("已断开") : nil),
            Item(symbol: "leaf", title: T("低电量"), value: model.reading?.lowPower?.text ?? "—",
                 note: model.lowPowerMismatch ? T("这一段要「%@」", ["\(model.wantedLowPower.shortTitle)"]) : nil,
                 tint: model.lowPowerMismatch ? .orange : .secondary),
        ]
    }

    var body: some View {
        Card(padding: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    Tile(symbol: item.symbol, title: item.title, value: item.value, note: item.note, tint: item.tint)
                }
            }
        }
    }

    private func powerValue(_ battery: BatterySnapshot) -> String {
        guard let watts = battery.watts, abs(watts) >= 0.1 else { return "0 W" }
        return String(format: "%+.1f W", watts)
    }

    private func currentNote(_ battery: BatterySnapshot) -> String? {
        var parts: [String] = []
        if let mA = battery.milliamps { parts.append(abs(mA) >= 1000 ? String(format: "%.2f A", Double(abs(mA)) / 1000) : "\(abs(mA)) mA") }
        if let mV = battery.millivolts { parts.append(String(format: "%.2f V", Double(mV) / 1000)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func cycleNote(_ battery: BatterySnapshot) -> String? {
        guard let cycles = battery.cycles else { return nil }
        return battery.designCycles.map { T("循环 %@ / %@", ["\(cycles)", "\($0)"]) } ?? T("循环 %@ 次", ["\(cycles)"])
    }

    private var thermalText: String? {
        switch model.reading?.thermal {
        case .fair: return T("系统有点热")
        case .serious: return T("系统很热")
        case .critical: return T("系统过热")
        default: return nil
        }
    }

    private func adapterValue(_ battery: BatterySnapshot) -> String {
        guard battery.externalConnected || model.adapterCut else { return T("电池") }
        if let watts = battery.adapterWatts { return "\(watts) W" }
        return T("已接通")
    }

    private var limitValue: String {
        switch model.reading?.chargeLimit {
        case .current(let value)?: return "\(value)%"
        case .unsupported?: return T("不支持")
        default: return "—"
        }
    }

    private var limitNote: String? {
        if case .unsupported? = model.reading?.chargeLimit { return T("这台机器没有") }
        return nil
    }
}

/// 最多三条短句，警告排在前面。
struct AdviceCard: View {
    var items: [AdviceItem]

    var body: some View {
        if !items.isEmpty {
            Card(padding: 12) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(tint(item.tone))
                            .frame(width: 18)
                        Text(item.text).lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func tint(_ tone: AdviceItem.Tone) -> Color {
        switch tone {
        case .good: return .green
        case .info: return .accentColor
        case .warn: return .orange
        }
    }
}

struct HistoryCard: View {
    @ObservedObject var model: AppModel

    private static let past: TimeInterval = 16 * 3600

    var body: some View {
        let end = model.reading?.date ?? Date()
        let samples = model.history.samples(since: end.addingTimeInterval(-Self.past))
        FoldCard(T("电量曲线"), key: "history", summary: T("过去 16 小时 + 预测")) {
            if samples.count < 2 {
                Text(T("开着一会儿就有曲线了。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                chart(samples: samples, end: end)
                HStack(spacing: 12) {
                    legend(color: .accentColor, text: T("电量"), dashed: false)
                    legend(color: .accentColor.opacity(0.6), text: T("预测"), dashed: true)
                    legend(color: .secondary, text: T("上限"), dashed: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 最多画 300 个点：曲线看起来一样，画起来快很多。
    static func thin(_ samples: [ChargeSample], to count: Int = 300) -> [ChargeSample] {
        guard samples.count > count else { return samples }
        let step = Int((Double(samples.count) / Double(count)).rounded(.up))
        var result = stride(from: 0, to: samples.count, by: step).map { samples[$0] }
        if let last = samples.last, result.last?.t != last.t { result.append(last) }
        return result
    }

    private func chart(samples: [ChargeSample], end: Date) -> some View {
        let plotted = Self.thin(samples)
        return Chart {
            ForEach(plotted, id: \.t) { sample in
                AreaMark(x: .value(T("时间"), sample.t), y: .value(T("电量"), sample.p))
                    .foregroundStyle(Color.accentColor.opacity(0.12))
                    .interpolationMethod(.monotone)
                LineMark(x: .value(T("时间"), sample.t), y: .value(T("电量"), sample.p), series: .value(T("系列"), T("电量")))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                LineMark(x: .value(T("时间"), sample.t), y: .value(T("上限"), sample.l), series: .value(T("系列"), T("上限")))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .interpolationMethod(.stepEnd)
            }
            ForEach(model.forecast, id: \.minutesAhead) { point in
                LineMark(x: .value(T("时间"), end.addingTimeInterval(Double(point.minutesAhead) * 60)),
                         y: .value(T("预测"), point.percent), series: .value(T("系列"), T("预测")))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            RuleMark(x: .value(T("现在"), end))
                .foregroundStyle(Color.primary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: end.addingTimeInterval(-Self.past)...end.addingTimeInterval(8 * 3600))
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 80, 100]) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)))
            }
        }
        .frame(height: 130)
        .accessibilityLabel(T("过去 16 小时的电量曲线，和之后几小时的预测"))
    }

    private func legend(color: Color, text: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
                .frame(width: 14, height: 2)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
