import SwiftUI
import BatteryCore

/// 智能：平时停在一个数字，拔电源前补到你要的量。习惯和细节收在下面，平时不用看。
struct SmartPanel: View {
    @ObservedObject var model: AppModel
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                Text(T("平时停在多少"))
                    .font(.headline)
                Text(T("平时停在这里，不一直满电。电池更耐用。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LimitPicker(presets: SmartPolicy.dailyCapChoices, range: SmartPolicy.dailyCapRange,
                            value: $model.settings.smartDailyCap)
            }

            Card {
                Text(T("拔电源时要多少"))
                    .font(.headline)
                Text(T("在你平时拔电源之前，把电补到这个量。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LimitPicker(presets: ChargePlanner.targetChoices, range: ChargePlanner.targetRange,
                            value: $model.settings.unplugTarget)
                if let note = model.customLimitNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                habitLine
                DisclosureGroup(isExpanded: $showDetails) {
                    habitDetails
                } label: {
                    Text(T("习惯和细节"))
                }
            }
        }
    }

    @ViewBuilder private var habitLine: some View {
        if !model.settings.learnHabits {
            Text(T("已关闭学习，只按设定的时间来。"))
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if model.learnProgress.learned, let learned = model.learnedUnplug {
            Text(T("已经学会：你平时大约 %@ 前后拔电源。", ["\(learned.display)"]))
                .font(.callout)
        } else {
            Text(T("还在学：一共记下 %@ 次，还差 %@ 次。", ["\(model.learnProgress.recorded)", "\(max(0, model.learnProgress.needed - model.learnProgress.bestCluster))"]))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// 习惯和细节：学没学会、依据是什么、最近记了哪几次、没给提醒的原因。
    private var habitDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(T("记住我的充电习惯"), isOn: $model.settings.learnHabits)
            Text(T("每天第一次接着电源超过 30 分钟后拔掉，记作一次。一小时之内记满 %@ 次，就学会你平时拔电源的时间。学到的只存在这台 Mac 上。", ["\(HabitJournal.minLearnCount)"]))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            learnBasis
            recentUnplugs
            Divider()
            tipsSection
            Divider()
            Toggle(T("还没学会时，先按一个固定时间"), isOn: $model.settings.deadlineEnabled)
            if model.settings.deadlineEnabled {
                DatePicker(T("平时拔电源的时间"), selection: ClockPicker.binding($model.settings.deadline),
                           displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .fixedSize()
                    .environment(\.locale, ClockPicker.locale)
            }
            if model.learnProgress.recorded > 0 {
                Button(T("重新学习")) { model.forgetHabits() }
                    .controlSize(.small)
            }
        }
        .padding(.top, 6)
    }

    /// 学习的依据：一共记下几次，一小时之内最多几次。没学会时说清楚还差什么。
    @ViewBuilder private var learnBasis: some View {
        let progress = model.learnProgress
        if !model.settings.learnHabits {
            EmptyView()
        } else if progress.recorded == 0 {
            Text(T("还没有记录。下次接着电源超过 30 分钟后拔掉，就会记在下面。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(T("依据：一共记下 %@ 次拔电源，其中一小时之内最多的一群有 %@ 次（学会需要 %@ 次）。",
                   ["\(progress.recorded)", "\(progress.bestCluster)", "\(progress.needed)"]))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 最近几次拔电源，从新到旧，带着日期。
    @ViewBuilder private var recentUnplugs: some View {
        let events = model.recentUnplugs
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(T("最近拔电源"))
                    .font(.caption.weight(.semibold))
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    Text("\(String(event.day.dropFirst(5)))  \(ClockTime(minuteOfDay: event.minute).display)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 温馨提醒。够用的记录不够时，直接说还差几天，不让人以为功能坏了。
    @ViewBuilder private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("温馨提醒"))
                .font(.caption.weight(.semibold))
            if model.tips.isEmpty {
                Text(T("记录够了就会在这里给提醒。需要最近 7 天里至少 %@ 天，每天用电或接电合计 2 小时以上；现在有 %@ 天。",
                       ["\(HabitTips.minDays)", "\(model.usableDays)"]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.tips) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: tip.symbol)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tip.title)
                                .font(.callout.weight(.semibold))
                            Text(tip.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

/// 固定：按一天里的时间段排上限，外加拔电源前充满。
struct FixedPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScheduleEditor(model: model)

            Card {
                Toggle(T("拔电源前充满"), isOn: $model.settings.deadlineEnabled)
                Text(T("到这个时间之前，按时间表提前开始补到下面的目标，好带着满电出门。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.settings.deadlineEnabled {
                    DatePicker(T("拔电源的时间"), selection: ClockPicker.binding($model.settings.deadline),
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .fixedSize()
                        .environment(\.locale, ClockPicker.locale)
                    Text(T("充到"))
                        .font(.callout)
                    LimitPicker(presets: ChargePlanner.targetChoices, range: ChargePlanner.targetRange,
                                value: $model.settings.unplugTarget)
                    if let note = model.customLimitNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// 一直充满：不管什么时候都充到 100%。
struct FullPanel: View {
    var body: some View {
        Card {
            Text(T("一直充到 100%"))
                .font(.headline)
            Text(T("接上电源就充满。适合台式机，或者一直插着用的机器。电池偏热（35°C 以上）时会先停在 80%，凉下来再接着充。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(T("长期挂在满电会让电池老化得快，平时用电池的话建议用智能模式。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
