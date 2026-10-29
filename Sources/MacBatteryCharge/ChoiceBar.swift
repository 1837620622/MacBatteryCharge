import SwiftUI

/// 一排等宽的选项，铺满整行。系统的分段控件不会拉宽，放在卡片里会一边空着，所以自己画：
/// 每一格等宽，选中的那一格有底色，切换时底色滑过去。
struct ChoiceBar<Value: Hashable>: View {
    var options: [Value]
    var title: (Value) -> String
    @Binding var selection: Value
    @Namespace private var highlight

    init(options: [Value], title: @escaping (Value) -> String, selection: Binding<Value>) {
        self.options = options
        self.title = title
        _selection = selection
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { value in
                let selected = value == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = value }
                } label: {
                    Text(title(value))
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.12))
                                    .matchedGeometryEffect(id: "highlight", in: highlight)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : .isButton)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        .frame(maxWidth: .infinity)
    }
}
