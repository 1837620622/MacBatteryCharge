import SwiftUI
import BatteryCore

/// 智能：平时停在日常上限，记住平时几点拔电源，离电前自动备电。
struct SmartPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                Text(T("日常上限"))
                    .font(.headline)
                Text(T("平时停在这里，不一直满电。电池更耐用。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker(T("日常上限"), selection: dailyCapBinding) {
                    ForEach(SmartPolicy.dailyCapChoices, id: \.self) { value in
                        Text("\(value)%").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Card {
                Text(T("离电前备电"))
                    .font(.headline)
                habitLine
                Toggle(T("记住我的充电习惯"), isOn: $model.settings.learnHabits)
                Text(T("每天第一次长时间接着电源后拔掉，就记作一次。学满 %@ 次，就按平时的时间备电。", ["\(HabitJournal.minLearnCount)"]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Picker(T("离电时充到"), selection: $model.settings.unplugTarget) {
                    ForEach(ChargePlanner.targetChoices, id: \.self) { value in
                        Text("\(value)%").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Toggle(T("还没学会时，按一个固定时间备电"), isOn: $model.settings.deadlineEnabled)
                if model.settings.deadlineEnabled {
                    DatePicker(T("默认拔电时间"), selection: ClockPicker.binding($model.settings.deadline),
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .fixedSize()
                }
                if model.learnedCount > 0 {
                    Button(T("重新学习")) { model.forgetHabits() }
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder private var habitLine: some View {
        if let learned = model.learnedUnplug {
            Text(T("已经学会：你平时大约 %@ 前后拔电源。", ["\(learned.text)"]))
                .font(.callout)
        } else if model.settings.learnHabits {
            Text(T("还在学：已记下 %@ 次。", ["\(model.learnedCount)"]))
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Text(T("已关闭学习，按下面的默认时间备电。"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var dailyCapBinding: Binding<Int> {
        Binding(get: { model.settings.smartDailyCap }, set: { model.settings.smartDailyCap = $0 })
    }
}

/// 固定：按一天里的时间段排上限，外加断电前充满。
struct FixedPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScheduleEditor(model: model)

            Card {
                Toggle(T("断电前充满"), isOn: $model.settings.deadlineEnabled)
                Text(T("到这个时间之前，按时间表放开到下面的目标，好带着满电离开。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.settings.deadlineEnabled {
                    HStack(spacing: 12) {
                        DatePicker(T("断电时间"), selection: ClockPicker.binding($model.settings.deadline),
                                   displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                            .fixedSize()
                        Picker(T("充到"), selection: $model.settings.unplugTarget) {
                            ForEach(ChargePlanner.targetChoices, id: \.self) { value in
                                Text("\(value)%").tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
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
