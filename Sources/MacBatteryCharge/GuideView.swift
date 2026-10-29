import SwiftUI
import BatteryCore

/// 第一次打开时的三步引导。只说要用的，不放动画，读完点「开始使用」就关。
/// 第二步顺便问一句平时几点拔电源，不靠猜。
struct GuideView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(T("欢迎使用%@", ["\(AppInfo.name)"]))
                    .font(.title2.weight(.semibold))
                Text(GuideCopy.intro)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(GuideCopy.titles.enumerated()), id: \.offset) { index, title in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.accentColor.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                        Text(GuideCopy.bodies[index])
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if index == 1 {
                            unplugQuestion
                                .padding(.top, 6)
                        }
                    }
                }
            }
            HStack {
                Spacer(minLength: 0)
                Button(T("开始使用")) { model.finishGuide() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    /// 问一句平时几点拔电源。先显示的是默认值，用户可以改，不用猜。
    private var unplugQuestion: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(T("你平时大约几点拔电源？"))
                DatePicker("", selection: ClockPicker.binding($model.settings.deadline),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .fixedSize()
            }
            Text(T("随便填一个就行，之后会自己学。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
