import SwiftUI
import BatteryCore

struct ScheduleCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FoldCard("时间表", key: "schedule", summary: model.limitLine) {
            TimelineBar(schedule: model.schedule, minute: model.minute,
                        selectedIndex: model.schedule.intervals.firstIndex { $0.id == model.editingID }) { index in
                let id = model.schedule.intervals[index].id
                withAnimation(.easeInOut(duration: 0.2)) { model.editingID = model.editingID == id ? nil : id }
            }
            Text("空档按 100%")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if model.settings.intervals.isEmpty {
                Text("没有时间段，全天 100%。")
                    .font(.callout)
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
                    .help("06:00–21:00 停在 80%，21:00–06:00 放开到 100%。")
            }
            .controlSize(.small)
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

    private var subtitle: String? {
        var parts: [String] = []
        if item.discharge && item.limit < 100 { parts.append("放电") }
        if item.lowPower != .off { parts.append("低电量\(item.lowPower.shortTitle)") }
        if isCurrent { parts.append("现在") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

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
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.rangeText).monospacedDigit()
                        if let subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        }
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
            .accessibilityLabel("第 \(number) 段，\(item.rangeText)，上限 \(item.limit)%")
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
                ToggleRow(title: "高于上限时放电",
                          info: "接着电源也用电池放到上限，最低 20%。要装放电帮手。",
                          isOn: $item.discharge)
                if item.discharge && !helperReady {
                    Button("安装放电帮手…", action: onInstallHelper).controlSize(.small)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("低电量").font(.subheadline).foregroundStyle(.secondary)
                    InfoButton(text: "只在点「立即应用」时改，会弹系统的管理员密码框。")
                }
                Picker("低电量", selection: $item.lowPower) {
                    ForEach(LowPowerChoice.allCases, id: \.self) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
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
