import SwiftUI

struct TodoView: View {
    let todoViewModel: TodoViewModel
    @State private var hoveredID: UUID? = nil

    var body: some View {
        Group {
            if todoViewModel.items.isEmpty {
                VStack {
                    Spacer()
                    Text("TODO が見つかりません")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kobaMute)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(todoViewModel.items) { item in
                            todoRow(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color.kobaSidebar)
    }

    @ViewBuilder
    private func todoRow(_ item: TodoItem) -> some View {
        let badgeColor = item.label == "FIXME" ? Color.orange : Color.kobaAccent

        HStack(spacing: 8) {
            Text(item.label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(badgeColor.opacity(0.12))
                )

            Text("L" + String(item.line))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.kobaMute)

            Text(item.text)
                .font(.system(size: 12))
                .foregroundStyle(Color.kobaInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(
            hoveredID == item.id
                ? Color.kobaInk.opacity(0.06)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredID = hovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .onTapGesture {
            NotificationCenter.default.post(
                name: .jumpToLine,
                object: nil,
                userInfo: ["line": item.line]
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.label) \(item.text) \(item.line)行目")
    }
}
