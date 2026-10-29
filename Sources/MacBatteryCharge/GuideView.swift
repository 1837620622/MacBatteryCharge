import SwiftUI
import BatteryCore

/// 第一次打开时的三步引导。只说要用的，不放动画，读完点「开始使用」就关。
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
}
