import SwiftUI

struct OutlineItem {
    let title: String
    let level: Int
    let lineNumber: Int
}

struct OutlineView: View {
    @Binding var text: String
    let onSelect: (Int) -> Void
    @State private var selectedLine: Int?

    private var headings: [OutlineItem] {
        let lines = text.components(separatedBy: .newlines)
        return lines.enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let hashes = trimmed.prefix { $0 == "#" }.count
            guard hashes >= 1, hashes <= 4,
                  trimmed.count > hashes,
                  trimmed.dropFirst(hashes).first == " " else { return nil }
            let title = trimmed.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return OutlineItem(title: String(title), level: hashes, lineNumber: index + 1)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if headings.isEmpty {
                    Text("No headings")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kobaMute)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    ForEach(headings, id: \.lineNumber) { item in
                        Button {
                            selectedLine = item.lineNumber
                            onSelect(item.lineNumber)
                        } label: {
                            HStack(spacing: 0) {
                                if item.level > 1 {
                                    Color.clear.frame(width: CGFloat(item.level - 1) * 12)
                                }
                                Text(item.title)
                                    .font(.system(size: item.level == 1 ? 13 : 12, weight: item.level == 1 ? .semibold : .regular))
                                    .foregroundStyle(selectedLine == item.lineNumber ? Color.kobaAccent : Color.kobaInk)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}
