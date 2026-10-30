import SwiftUI
import BatteryCore

/// 第一次打开时的引导，共五页：是什么、怎么运行、怎么设置、怎么学习、其他。可以翻页，也能跳过；设置里能再看一次。
/// 「怎么设置」那一页直接放上两个数字，「怎么学习」那一页问一句平时几点拔电源，不靠猜。
struct GuideView: View {
    @ObservedObject var model: AppModel
    @State private var page = 0

    private var lastPage: Int { GuideCopy.titles.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(GuideCopy.titles[page])
                        .font(.headline)
                    Text(GuideCopy.bodies[page])
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    pageExtra
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            footer
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(T("欢迎使用%@", ["\(AppInfo.name)"]))
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 8)
                if page < lastPage {
                    Button(T("跳过")) { model.finishGuide() }
                        .buttonStyle(.link)
                        .controlSize(.small)
                }
            }
            Text(GuideCopy.intro)
                .font(.caption)
                .foregroundStyle(.secondary)
            pageDots
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0...lastPage, id: \.self) { index in
                Circle()
                    .fill(index == page ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
            Text(T("第 %@ 页，共 %@ 页", ["\(page + 1)", "\(lastPage + 1)"]))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
        }
    }

    /// 这一页要的额外内容：「怎么设置」放上两个数字，「怎么学习」问一句平时几点拔电源。
    @ViewBuilder private var pageExtra: some View {
        switch page {
        case 2:
            VStack(alignment: .leading, spacing: 10) {
                Text(T("平时停在多少"))
                    .font(.callout.weight(.semibold))
                LimitPicker(presets: SmartPolicy.dailyCapChoices, range: SmartPolicy.dailyCapRange,
                            value: $model.settings.smartDailyCap)
                Text(T("拔电源时要多少"))
                    .font(.callout.weight(.semibold))
                    .padding(.top, 4)
                LimitPicker(presets: ChargePlanner.targetChoices, range: ChargePlanner.targetRange,
                            value: $model.settings.unplugTarget)
                Text(T("随时可以在主窗口里改。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case 3:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(T("你平时大约几点拔电源？"))
                        .fixedSize(horizontal: false, vertical: true)
                    DatePicker("", selection: ClockPicker.binding($model.settings.deadline),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .fixedSize()
                        .environment(\.locale, ClockPicker.locale)
                }
                Text(T("随便填一个就行，之后会自己学。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack {
            if page > 0 {
                Button(T("上一页")) { page -= 1 }
                    .controlSize(.large)
            }
            Spacer(minLength: 0)
            if page < lastPage {
                Button(T("下一页")) { page += 1 }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            } else {
                Button(T("开始使用")) { model.finishGuide() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
    }
}
