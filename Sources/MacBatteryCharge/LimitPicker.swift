import SwiftUI
import BatteryCore

/// 一排常用档位，最后一格是「自定义」。选了自定义，下面出现一个数字框和加减，想停到多少就填多少。
/// 填的数夹到 `range` 里，超出的自动收回来。
struct LimitPicker: View {
    var presets: [Int]
    var range: ClosedRange<Int>
    @Binding var value: Int
    @State private var customMode: Bool

    init(presets: [Int], range: ClosedRange<Int>, value: Binding<Int>) {
        self.presets = presets
        self.range = range
        _value = value
        // 一开始就是预设里没有的数，说明之前是自定义的，保持自定义。
        _customMode = State(initialValue: !presets.contains(value.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChoiceBar(options: presets.map(Choice.preset) + [.custom], title: { $0.title }, selection: selection)
            // 输入框是系统控件。选「自定义」时它跟着选中的动画走出来，会花，所以出现和消失都不做过渡。
            if customMode {
                HStack(spacing: 8) {
                    TextField("", value: clamped, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 64)
                    Text("%")
                    Stepper("", value: clamped, in: range)
                        .labelsHidden()
                    Text(T("可以填 %@ 到 %@%", ["\(range.lowerBound)", "\(range.upperBound)"]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.identity)
            }
        }
    }

    private enum Choice: Hashable {
        case preset(Int)
        case custom

        var title: String {
            switch self {
            case .preset(let value): return "\(value)%"
            case .custom: return T("自定义")
            }
        }
    }

    private var selection: Binding<Choice> {
        Binding(
            get: { customMode ? .custom : .preset(value) },
            set: { choice in
                switch choice {
                case .preset(let preset):
                    customMode = false
                    value = preset
                case .custom:
                    customMode = true
                }
            }
        )
    }

    /// 输入框和加减共用：写进去的数先夹到范围里。
    private var clamped: Binding<Int> {
        Binding(
            get: { value },
            set: { value = min(range.upperBound, max(range.lowerBound, $0)) }
        )
    }
}
