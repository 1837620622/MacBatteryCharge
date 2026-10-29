import SwiftUI
import BatteryCore

/// 固定模式的时间段。每一段：开始、结束、停在多少。没排到的时间按 100%。
struct ScheduleEditor: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Card {
            HStack {
                Text(T("时间段"))
                    .font(.headline)
                Spacer(minLength: 0)
                Button(T("恢复默认")) { model.resetSchedule() }
                    .controlSize(.small)
            }
            Text(T("每一段停在这里的上限。没排到的时间按 100% 充。"))
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach($model.settings.intervals) { binding in
                IntervalRow(item: binding, dischargeAvailable: model.helperUsable) {
                    model.removeInterval(binding.wrappedValue.id)
                }
            }
            HStack(spacing: 10) {
                Button {
                    model.addInterval()
                } label: {
                    Label(T("加一段"), systemImage: "plus")
                }
                .controlSize(.small)
                .disabled(!model.canAddInterval)
                if let hint = model.addHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// 一段的一行：时间范围、上限、要不要用电池放电。
struct IntervalRow: View {
    @Binding var item: Interval
    var dischargeAvailable: Bool
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            DatePicker("", selection: ClockPicker.binding($item.start), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
            Text("–")
                .foregroundStyle(.secondary)
            DatePicker("", selection: ClockPicker.binding($item.end), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .fixedSize()
            Picker("", selection: $item.limit) {
                ForEach(Schedule.allowedLimits, id: \.self) { value in
                    Text("\(value)%").tag(value)
                }
            }
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
            if dischargeAvailable {
                Toggle(T("放电"), isOn: $item.discharge)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help(T("接着电源、电量高于上限时，用电池放到上限再停住。"))
            }
            Button(action: remove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(T("删掉这一段"))
        }
        .padding(.vertical, 2)
    }
}
