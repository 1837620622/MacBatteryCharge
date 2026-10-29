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
        .background(Color(nsColor: .windowBackgroundColor))
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
                if let tonight = model.tonight { TonightCard(tonight: tonight) }

                FoldHeader(title: "上排", subtitle: "读数", summary: topSummary, open: $topOpen)
                if topOpen {
                    VStack(alignment: .leading, spacing: 12) {
                        ReadingsCard(model: model)
                        let advice = model.advice
                        if !advice.isEmpty { AdviceCard(items: advice) }
                        HistoryCard(model: model)
                    }
                    .transition(.opacity)
                }

                Divider().padding(.vertical, 2)

                FoldHeader(title: "下排", subtitle: "时间表和设置", summary: bottomSummary, open: $bottomOpen)
                if bottomOpen {
                    VStack(alignment: .leading, spacing: 12) {
                        ScheduleCard(model: model)
                        HelperCard(model: model)
                        SmartCard(model: model)
                        NotchCard(model: model)
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
        guard battery.present else { return "没有电池" }
        var parts = [battery.percent.map { "\($0)%" } ?? "—", battery.flow.menuWord]
        if let celsius = battery.celsius { parts.append(String(format: "%.0f°C", celsius)) }
        return parts.joined(separator: " · ")
    }

    private var bottomSummary: String {
        let count = model.settings.intervals.count
        var text = count == 0 ? "全天 100%" : "\(count) 段"
        if model.settings.deadlineEnabled { text += " · \(model.settings.deadline.text) 断电" }
        return text
    }
}

/// 上排、下排的标题。点一下整排收起，收起时右边写一句摘要。
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
        .accessibilityHint(open ? "收起" : "展开")
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
            .accessibilityHint(open ? "收起" : "展开")
            if open { content.transition(.opacity) }
        }
    }
}

// MARK: 顶部提示

struct BannerStack: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if !model.preview && Installation.shouldOfferMove {
            Banner(symbol: "folder.badge.plus", tint: .blue, title: "放进“应用程序”",
                   detail: "现在是从别处打开的。放进“应用程序”后，登录时才会自己打开，更新也装在同一个位置。") {
                Button(model.moving ? "正在放进去…" : "放进去并重新打开") { model.moveToApplications() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.moving)
            }
        }
        if model.dischargeWantedButMissing && model.helperInstallable && !model.preview {
            Banner(symbol: "arrow.down.to.line.compact", tint: .orange, title: "这一段要放电，还没装放电帮手",
                   detail: "没有它，电量高于 \(model.decision.limit)% 时只会停止充电，不会往下放。装一次要管理员密码。") {
                Button(model.helperBusy ? "正在安装…" : "安装放电帮手") { model.installHelper() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.helperBusy)
            }
        }
        if model.helperOutdated && !model.preview {
            Banner(symbol: "arrow.triangle.2.circlepath", tint: .orange, title: "放电帮手要更新",
                   detail: "软件升级后帮手的版本不一样了。更新时要一次管理员密码。") {
                Button(model.helperBusy ? "正在更新…" : "更新放电帮手") { model.installHelper() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.helperBusy)
            }
        }
        if let error = model.scheduleError {
            Banner(symbol: "exclamationmark.triangle.fill", tint: .red, title: "时间表有问题",
                   detail: "\(error.message)。改好之前，按上一次能用的时间表。") { EmptyView() }
        }
        switch model.update {
        case .available(let release):
            Banner(symbol: "arrow.down.circle.fill", tint: .accentColor, title: "有新版本 \(release.version)",
                   detail: Self.shortNotes(release.notes)) {
                Button("下载并安装") { model.install(release) }
                    .buttonStyle(.borderedProminent)
                Button("跳过这一版") { model.skip(release) }
                if let page = release.page {
                    Link("看说明", destination: page)
                }
            }
        case .downloading(let release, let progress):
            Banner(symbol: "arrow.down.circle", tint: .accentColor, title: "正在下载 \(release.version)", detail: nil) {
                ProgressView(value: progress)
                    .frame(maxWidth: .infinity)
                Text("\(Int(progress * 100))%").monospacedDigit().foregroundStyle(.secondary)
            }
        case .installing(let release):
            Banner(symbol: "shippingbox.fill", tint: .accentColor, title: "安装器已经打开",
                   detail: "按安装器的提示把 \(release.version) 装好，充电上限会自己重新打开。") { EmptyView() }
        case .failed(let text):
            Banner(symbol: "exclamationmark.circle.fill", tint: .orange, title: "更新没有完成", detail: text) {
                Button("重试") { model.checkForUpdates(userInitiated: true) }
            }
        default:
            EmptyView()
        }
    }

    static func shortNotes(_ notes: String) -> String? {
        let lines = notes.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#-* ")) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return lines.prefix(3).joined(separator: "\n")
    }
}

// MARK: 电量

struct HeroCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let battery = model.battery
        Card {
            HStack(spacing: 16) {
                BatteryRing(percent: battery.percent, limit: model.decision.limit, flow: battery.flow)
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.statusTitle)
                        .font(.title2.weight(.semibold))
                    Text(model.statusDetail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ReasonChip(text: model.limitLine, reason: model.decision.reason)
                }
                Spacer(minLength: 0)
            }
            if battery.present {
                HStack(spacing: 8) {
                    Button {
                        model.toggleTopUp()
                    } label: {
                        Label(model.topUpActive ? "结束临时充满" : "临时充满", systemImage: model.topUpActive ? "xmark.circle" : "bolt.fill")
                    }
                    .help("到下一次换段或拔掉电源之前，先放开到 100%。")
                    if model.systemLimitMismatch {
                        Label("系统现在是 \(model.reading?.chargeLimit.value ?? 0)%，马上改", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
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
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

struct TonightCard: View {
    var tonight: AppModel.Tonight

    private var tint: Color {
        switch tonight.tone {
        case .success: return .green
        case .info: return .indigo
        case .error: return .orange
        }
    }

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tonight.symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tonight.title).font(.headline)
                    Text(tonight.detail)
                        .foregroundStyle(.secondary)
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

    private struct Row: Identifiable {
        var name: String
        var value: String
        var symbol: String
        var tint: Color = .secondary
        var note: String?
        var id: String { name }
    }

    private var rows: [Row] {
        let battery = model.battery
        guard battery.present else {
            return [
                Row(name: "电量", value: "没有电池", symbol: "battery.0percent"),
                Row(name: "内存", value: model.reading?.memory.summary ?? "读取中", symbol: "memorychip"),
                Row(name: "系统上限", value: limitValue, symbol: "gauge.with.dots.needle.67percent", note: limitNote),
            ]
        }
        var rows: [Row] = []
        rows.append(Row(name: "电量", value: battery.percent.map { "\($0)%" } ?? "读取中", symbol: "battery.75percent", tint: .accentColor))
        rows.append(Row(name: "状态", value: battery.flow.sentence, symbol: "arrow.left.arrow.right"))
        rows.append(Row(name: "电流", value: currentText(battery), symbol: "bolt", note: voltageText(battery)))
        rows.append(Row(name: "健康", value: battery.health.map { "\($0)%" } ?? "没有读到", symbol: "heart",
                        tint: (battery.health ?? 100) < 80 ? .orange : .secondary, note: cycleText(battery)))
        rows.append(Row(name: "温度", value: battery.celsius.map { String(format: "%.1f°C", $0) } ?? "没有读到",
                        symbol: "thermometer.medium", tint: (battery.celsius ?? 0) >= 40 ? .orange : .secondary, note: thermalText))
        rows.append(Row(name: "内存", value: model.reading?.memory.summary ?? "读取中", symbol: "memorychip",
                        tint: (model.reading?.memory.pressure ?? 0) >= 4 ? .orange : .secondary))
        rows.append(Row(name: "电源", value: powerText(battery), symbol: "powerplug"))
        rows.append(Row(name: "系统上限", value: limitValue, symbol: "gauge.with.dots.needle.67percent", note: limitNote))
        rows.append(Row(name: "这一段", value: segmentText, symbol: "clock"))
        rows.append(Row(name: "低电量", value: lowPowerText, symbol: "leaf",
                        tint: model.lowPowerMismatch ? .orange : .secondary,
                        note: model.lowPowerMismatch ? "和这一段不同，点「立即应用」改" : nil))
        return rows
    }

    var body: some View {
        Card(padding: 12) {
            VStack(spacing: 7) {
                ForEach(rows) { row in
                    ReadingRow(name: row.name, value: row.value, symbol: row.symbol, tint: row.tint, note: row.note)
                    if row.id != rows.last?.id {
                        Divider().padding(.leading, 26)
                    }
                }
            }
        }
    }

    private func currentText(_ battery: BatterySnapshot) -> String {
        guard let mA = battery.milliamps else { return "没有读到" }
        if abs(mA) >= 1000 { return String(format: "%.2f A", Double(mA) / 1000) }
        return "\(mA) mA"
    }

    private func voltageText(_ battery: BatterySnapshot) -> String? {
        var parts: [String] = []
        if let mV = battery.millivolts { parts.append(String(format: "%.2f V", Double(mV) / 1000)) }
        if let watts = battery.watts, abs(watts) >= 0.1 { parts.append(String(format: "%.1f W", watts)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func cycleText(_ battery: BatterySnapshot) -> String? {
        var parts: [String] = []
        if let cycles = battery.cycles {
            parts.append(battery.designCycles.map { "循环 \(cycles) / \($0) 次" } ?? "循环 \(cycles) 次")
        }
        let points = model.history.health
        if points.count >= 2, let first = points.first, let last = points.last, first.health != last.health {
            parts.append("\(first.day) 起 \(first.health)% → \(last.health)%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private var thermalText: String? {
        switch model.reading?.thermal {
        case .fair: return "系统有点热"
        case .serious: return "系统很热"
        case .critical: return "系统过热"
        default: return nil
        }
    }

    private func powerText(_ battery: BatterySnapshot) -> String {
        guard battery.externalConnected else { return "电池" }
        if let watts = battery.adapterWatts { return "\(watts) W 充电器" }
        return "已接通"
    }

    private var limitValue: String {
        switch model.reading?.chargeLimit {
        case .current(let value)?: return "\(value)%"
        case .unsupported?: return "不支持"
        default: return "读取中"
        }
    }

    private var limitNote: String? {
        if case .unsupported(let text)? = model.reading?.chargeLimit { return text }
        return nil
    }

    private var segmentText: String {
        guard let item = model.currentInterval else { return "空档 · 100%" }
        return "\(item.rangeText) · \(item.limit)%"
    }

    private var lowPowerText: String {
        let system = model.reading?.lowPower?.text ?? "没有读到"
        return "系统 \(system) · 这一段 \(model.wantedLowPower.shortTitle)"
    }
}

struct AdviceCard: View {
    var items: [AdviceItem]

    var body: some View {
        Card(padding: 12) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(tint(item.tone))
                        .frame(width: 18)
                    Text(item.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
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
        let forecast = model.forecast
        FoldCard("电量曲线", key: "history", summary: "过去 16 小时和之后几小时") {
            HStack(spacing: 10) {
                Text("过去 16 小时 · 之后预测").font(.caption).foregroundStyle(.secondary)
                Spacer()
                legend(color: .accentColor, text: "电量", dashed: false)
                legend(color: .accentColor.opacity(0.55), text: "预测", dashed: true)
                legend(color: .secondary, text: "上限", dashed: false, thin: true)
            }
            if samples.count < 2 {
                Text("开着软件一段时间后，这里会画出电量和上限。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart {
                    ForEach(samples, id: \.t) { sample in
                        AreaMark(x: .value("时间", sample.t), y: .value("电量", sample.p))
                            .foregroundStyle(Color.accentColor.opacity(0.12))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("时间", sample.t), y: .value("电量", sample.p), series: .value("系列", "电量"))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("时间", sample.t), y: .value("上限", sample.l), series: .value("系列", "上限"))
                            .foregroundStyle(Color.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .interpolationMethod(.stepEnd)
                    }
                    ForEach(forecast, id: \.minutesAhead) { point in
                        LineMark(x: .value("时间", end.addingTimeInterval(Double(point.minutesAhead) * 60)),
                                 y: .value("预测", point.percent), series: .value("系列", "预测"))
                            .foregroundStyle(Color.accentColor.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    }
                    RuleMark(x: .value("现在", end))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, alignment: .leading, spacing: 0) {
                            Text("现在").font(.caption2).foregroundStyle(.secondary)
                        }
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
                .frame(height: 140)
                .accessibilityLabel("过去 16 小时的电量曲线，和之后几小时的预测")
            }
        }
    }

    private func legend(color: Color, text: String, dashed: Bool, thin: Bool = false) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: thin ? 1 : 2, dash: dashed ? [3, 2] : (thin ? [3, 2] : [])))
                .frame(width: 14, height: 2)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: 下排

struct ScheduleCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FoldCard("时间表", key: "schedule", summary: "\(model.limitLine)") {
            Text("空档按 100%。点时间条或下面的一行来改。").font(.caption).foregroundStyle(.secondary)
            TimelineBar(schedule: model.schedule, minute: model.minute,
                        selectedIndex: model.schedule.intervals.firstIndex { $0.id == model.editingID }) { index in
                let id = model.schedule.intervals[index].id
                withAnimation(.easeInOut(duration: 0.2)) { model.editingID = model.editingID == id ? nil : id }
            }
            if model.settings.intervals.isEmpty {
                Text("还没有时间段，全天按 100%。")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach($model.settings.intervals) { $item in
                    let id = item.id
                    let number = (model.settings.intervals.firstIndex { $0.id == id } ?? 0) + 1
                    IntervalRow(item: $item, number: number,
                                isCurrent: model.currentInterval?.id == id && model.scheduleError == nil,
                                isEditing: model.editingID == id,
                                helperReady: model.helperUsable,
                                onInstallHelper: { model.installHelper() },
                                onTap: { withAnimation(.easeInOut(duration: 0.2)) { model.editingID = model.editingID == id ? nil : id } },
                                onDelete: { withAnimation { model.removeInterval(id) } },
                                onCommit: { model.sortIntervals() })
                    if id != model.settings.intervals.last?.id {
                        Divider()
                    }
                }
            }
            HStack(spacing: 8) {
                Button {
                    withAnimation { model.addInterval() }
                } label: {
                    Label("加一段", systemImage: "plus")
                }
                .disabled(!model.canAddInterval)
                if let hint = model.addHint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("恢复默认") { withAnimation { model.resetSchedule() } }
                    .help("06:00 到 21:00 停在 80%，21:00 到次日 06:00 放开到 100%。")
            }
        }
    }
}

struct IntervalRow: View {
    @Binding var item: Interval
    var number: Int
    var isCurrent: Bool
    var isEditing: Bool
    var helperReady: Bool
    var onInstallHelper: () -> Void
    var onTap: () -> Void
    var onDelete: () -> Void
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(isCurrent ? Color.accentColor : Color.primary.opacity(0.1)))
                        .foregroundStyle(isCurrent ? Color.white : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.rangeText).monospacedDigit()
                        Text("低电量 \(item.lowPower.shortTitle)" + (item.discharge ? " · 放电" : "") + (isCurrent ? " · 现在这一段" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(item.limit)%")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isEditing ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("第 \(number) 段，\(item.rangeText)，上限 \(item.limit)%，低电量\(item.lowPower.title)")
            .accessibilityHint(isEditing ? "收起" : "展开编辑")

            if isEditing {
                IntervalEditor(item: $item, helperReady: helperReady, onInstallHelper: onInstallHelper, onDelete: onDelete)
                    .onDisappear(perform: onCommit)
            }
        }
        .padding(.vertical, 8)
    }
}

struct IntervalEditor: View {
    @Binding var item: Interval
    var helperReady: Bool
    var onInstallHelper: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimeField(title: "开始", time: $item.start)
            TimeField(title: "结束", time: $item.end)
            VStack(alignment: .leading, spacing: 6) {
                Text("上限").font(.subheadline).foregroundStyle(.secondary)
                Picker("上限", selection: $item.limit) {
                    ForEach(Schedule.allowedLimits, id: \.self) { Text("\($0)%").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if item.limit < 100 {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $item.discharge) {
                        OptionLabel(title: "高于上限时放电",
                                    detail: "接着电源也用电池，放到 \(item.limit)% 就停。只在这一段、放电帮手装好时生效。")
                    }
                    .toggleStyle(.switch)
                    if item.discharge && !helperReady {
                        Button("安装放电帮手…", action: onInstallHelper).controlSize(.small)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("这一段的低电量").font(.subheadline).foregroundStyle(.secondary)
                Picker("低电量", selection: $item.lowPower) {
                    ForEach(LowPowerChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("低电量只在点「立即应用」时改，会弹出系统的管理员密码框。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("删掉这一段", systemImage: "trash")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

/// 小时、分钟两个下拉，旁边一个表盘按钮。
struct TimeField: View {
    var title: String
    @Binding var time: ClockTime
    @State private var showDial = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title).frame(width: 36, alignment: .leading)
            Picker("\(title)小时", selection: hour) {
                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 66)
            Text(":").foregroundStyle(.secondary)
            Picker("\(title)分钟", selection: minute) {
                ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 66)
            Button {
                showDial.toggle()
            } label: {
                Image(systemName: "clock")
            }
            .help("用表盘选时间")
            .accessibilityLabel("用表盘选\(title)时间")
            .popover(isPresented: $showDial, arrowEdge: .bottom) {
                VStack(spacing: 8) {
                    DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    Text(time.text).font(.title3.weight(.semibold)).monospacedDigit()
                }
                .padding(14)
            }
            Spacer(minLength: 0)
        }
    }

    private var hour: Binding<Int> {
        Binding(get: { time.hour }, set: { time = ClockTime(hour: $0, minute: time.minute) })
    }

    private var minute: Binding<Int> {
        Binding(get: { time.minute }, set: { time = ClockTime(hour: time.hour, minute: $0) })
    }

    private var date: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
        }, set: {
            time = ClockTime(minuteOfDay: currentMinute($0))
        })
    }
}

struct SmartCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FoldCard("聪明一点", key: "smart", defaultOpen: false,
                 summary: model.settings.deadlineEnabled ? "\(model.settings.deadline.text) 断电前充满" : "断电前充满：关") {
            Toggle(isOn: $model.settings.deadlineEnabled) {
                OptionLabel(title: "断电前充满",
                            detail: "按这台机器自己的充电速度，必要时比时间表早一点放开，只往上放。")
            }
            if model.settings.deadlineEnabled {
                TimeField(title: "断电", time: $model.settings.deadline)
                    .padding(.leading, 2)
            }
            Divider()
            Toggle(isOn: $model.settings.heatProtection) {
                OptionLabel(title: "过热保护", detail: "接着电源且电池到 40°C 时先停在 80%，降到 37°C 再按时间表。")
            }
            Divider()
            Toggle(isOn: $model.settings.notifications) {
                OptionLabel(title: "通知", detail: "停在上限、提前放开、过热时发一条系统通知。打开时才会问通知权限。")
            }
        }
        .toggleStyle(.switch)
    }
}

struct HelperCard: View {
    @ObservedObject var model: AppModel

    private var summary: String {
        if model.helperOutdated { return "要更新" }
        guard let helper = model.helper else { return "没装" }
        return helper.adapterControl ? "已装" : "已装，这台不支持"
    }

    private var detail: String {
        guard let helper = model.helper else {
            return "接着电源也把电放到上限，要靠这个以 root 运行的小程序断开电源适配器。装一次要管理员密码，只有这一个密码框。"
        }
        if !helper.adapterControl { return "已装，但这台 Mac 的 SMC 里找不到断开电源的开关，放电用不了。仍然只会停止充电。" }
        if helper.adapterEnabled == false { return "正在放电：电源适配器暂时断开，放到上限就接回。" }
        return "已装好。需要放电时才断开电源适配器，放到上限就接回；睡眠、退出或 2 分钟收不到指令都会自动接回。"
    }

    var body: some View {
        FoldCard("放电帮手", key: "helper", defaultOpen: model.helper == nil, summary: summary) {
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = model.helper?.error {
                Text("最近一次出错：\(error)").font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                if model.helper == nil || model.helperOutdated {
                    Button(model.helperBusy ? "正在安装…" : (model.helperOutdated ? "更新放电帮手" : "安装放电帮手")) { model.installHelper() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.helperBusy || !model.helperInstallable)
                    if !model.helperInstallable {
                        Text(SystemReaders.isAppleSilicon ? "这份软件里没有帮手" : "只支持 Apple 芯片")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.helper != nil {
                    Button("卸载放电帮手", role: .destructive) { model.removeHelper() }
                        .disabled(model.helperBusy)
                }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
    }
}

struct NotchCard: View {
    @ObservedObject var model: AppModel

    private var summary: String {
        let settings = model.settings
        if settings.notchIsland { return "灵动岛 开" }
        return settings.notchEars ? "两侧小字" : "关"
    }

    var body: some View {
        FoldCard("刘海", key: "notch", defaultOpen: false, summary: summary) {
            Toggle(isOn: $model.settings.notchIsland) {
                OptionLabel(title: "刘海灵动岛", detail: "鼠标移到刘海上，从刘海里展开电量、上限和今晚的计划。只读鼠标位置，不要任何隐私权限。")
            }
            Toggle(isOn: $model.settings.notchOnPower) {
                OptionLabel(title: "插拔电源时弹一下", detail: "插上或拔掉电源时，灵动岛自己展开几秒。")
            }
            .disabled(!model.settings.notchIsland)
            Toggle(isOn: $model.settings.notchEars) {
                OptionLabel(title: "刘海两侧常驻小字", detail: "左边是上限，右边是充电、放电或接通。会盖住刘海两边一小块菜单栏。")
            }
            Toggle(isOn: $model.settings.notchWithoutNotch) {
                OptionLabel(title: "没有刘海的屏幕也用", detail: "在菜单栏正中虚拟一个，外接显示器或旧款 Mac 也能用。")
            }
        }
        .toggleStyle(.switch)
    }
}

struct OptionLabel: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SystemCard: View {
    @ObservedObject var model: AppModel

    private var loginDetail: String {
        if let note = model.loginNote { return note }
        switch model.loginState {
        case .on: return "已登记在系统设置的“登录项”里。登录时只出现在菜单栏，不开窗口。"
        case .off: return "关着。"
        case .needsApproval: return "要在系统设置的“登录项”里允许。"
        case .needsApplications: return "放进“应用程序”后，登录时才会自己打开。"
        }
    }

    private var updateText: String? {
        switch model.update {
        case .checking: return "正在查…"
        case .upToDate: return "已是最新"
        case .available(let release): return "有新版本 \(release.version)"
        default: return nil
        }
    }

    var body: some View {
        FoldCard("系统", key: "system", defaultOpen: false, summary: "版本 \(Installation.version)") {
            Toggle(isOn: $model.settings.launchAtLogin) {
                OptionLabel(title: "登录时打开", detail: loginDetail)
            }
            if model.loginState == .needsApproval {
                Button("打开登录项设置") { LoginItem.openSystemSettings() }
                    .controlSize(.small)
            }
            Divider()
            Toggle(isOn: $model.settings.autoCheckUpdates) {
                OptionLabel(title: "自动检查更新", detail: "打开窗口时每天最多查一次 GitHub。登录时不查，也不弹窗。")
            }
            HStack(spacing: 8) {
                Text("版本 \(Installation.version)").foregroundStyle(.secondary).monospacedDigit()
                if let updateText {
                    Text(updateText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("检查更新") { model.checkForUpdates(userInitiated: true) }
                    .disabled(model.update == .checking)
            }
            Divider()
            HStack(spacing: 8) {
                Button("再看一遍引导") { model.replayGuide() }
                Spacer()
                Button("卸载…", role: .destructive) { model.uninstall() }
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .toggleStyle(.switch)
    }
}

// MARK: 底部

struct FooterBar: View {
    @ObservedObject var model: AppModel

    private var tint: Color {
        switch model.message?.tone {
        case .success?: return .green
        case .error?: return .red
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = model.message {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: message.tone == .error ? "exclamationmark.circle.fill" : (message.tone == .success ? "checkmark.circle.fill" : "info.circle.fill"))
                        .foregroundStyle(tint)
                    Text(message.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        model.dismissMessage()
                    } label: {
                        Image(systemName: "xmark").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("关掉这条提示")
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(segmentLine).font(.callout).monospacedDigit()
                    Text(model.lowPowerMismatch ? "低电量和系统不同，会弹出管理员密码框" : "上限换段时自动写，不要密码")
                        .font(.caption)
                        .foregroundStyle(model.lowPowerMismatch ? Color.orange : Color.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    model.applyNow()
                } label: {
                    HStack(spacing: 6) {
                        if model.applying { ProgressView().controlSize(.small) }
                        Text("立即应用")
                    }
                    .frame(minWidth: 84)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.applying)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var segmentLine: String {
        let low = model.wantedLowPower.shortTitle
        guard let item = model.currentInterval else { return "现在是空档 · 100% · 低电量\(low)" }
        return "这一段 \(item.rangeText) · \(item.limit)% · 低电量\(low)"
    }
}
