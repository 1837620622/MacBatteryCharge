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
                Picker(T("平时停在多少"), selection: dailyCapBinding) {
                    ForEach(SmartPolicy.dailyCapChoices, id: \.self) { value in
                        Text("\(value)%").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Card {
                Text(T("拔电源时要多少"))
                    .font(.headline)
                Text(T("在你平时拔电源之前，把电补到这个量。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker(T("拔电源时充到"), selection: $model.settings.unplugTarget) {
                    ForEach(ChargePlanner.targetChoices, id: \.self) { value in
                        Text("\(value)%").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                habitLine
                DisclosureGroup(isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(T("记住我的充电习惯"), isOn: $model.settings.learnHabits)
                        Text(T("每天第一次长时间接着电源后拔掉，就记作一次。同一个半小时里记满 %@ 次，就按那个时间来。", ["\(HabitJournal.minLearnCount)"]))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle(T("还没学会时，先按一个固定时间"), isOn: $model.settings.deadlineEnabled)
                        if model.settings.deadlineEnabled {
                            DatePicker(T("平时拔电源的时间"), selection: ClockPicker.binding($model.settings.deadline),
                                       displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                                .fixedSize()
                                .environment(\.locale, ClockPicker.locale)
                        }
                        if model.learnedCount > 0 {
                            Button(T("重新学习")) { model.forgetHabits() }
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text(T("习惯和细节"))
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
            Text(T("已关闭学习，只按设定的时间来。"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var dailyCapBinding: Binding<Int> {
        Binding(get: { model.settings.smartDailyCap }, set: { model.settings.smartDailyCap = $0 })
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
                    Picker(T("充到"), selection: $model.settings.unplugTarget) {
                        ForEach(ChargePlanner.targetChoices, id: \.self) { value in
                            Text("\(value)%").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
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
