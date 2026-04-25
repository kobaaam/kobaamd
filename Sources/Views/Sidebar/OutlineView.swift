import SwiftUI

struct OutlineView: View {
    @Environment(AppViewModel.self) private var appViewModel
    let outlineViewModel: OutlineViewModel
    @State private var hoveredID: UUID? = nil

    var body: some View {
        Group {
            if outlineViewModel.items.isEmpty {
                VStack {
                    Spacer()
                    Text("見出しが見つかりません")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kobaMute)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(outlineViewModel.items) { item in
                            HStack(spacing: 8) {
                                Text("H\(item.level)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Color.kobaAccent)
                                    .frame(width: 24, alignment: .leading)

                                Text(item.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.kobaInk)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("L\(item.line)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Color.kobaMute)
                            }
                            .padding(.leading, CGFloat(item.level - 1) * 12 + 10)
                            .padding(.trailing, 10)
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
                                if outlineViewModel.totalLines > 1 {
                                    appViewModel.previewScrollRatio = Double(item.line - 1) / Double(outlineViewModel.totalLines - 1)
                                }
                                NotificationCenter.default.post(
                                    name: .jumpToLine,
                                    object: nil,
                                    userInfo: ["line": item.line]
                                )
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("H\(item.level) \(item.text) \(item.line)行目")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color.kobaSidebar)
    }
}
