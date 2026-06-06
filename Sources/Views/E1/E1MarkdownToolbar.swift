import SwiftUI

// MARK: - E1 Markdown formatting toolbar (Gemini layout spec)

struct E1MarkdownToolbar: View {
    var body: some View {
        HStack(spacing: 4) {
            toolbarButton("bold", help: "太字 (⌘B)") { AppCommand.toggleBold.post() }
            toolbarButton("italic", help: "斜体 (⌘I)") { AppCommand.toggleItalic.post() }
            toolbarButton("link", help: "リンク (⌘K)") { AppCommand.insertLink.post() }
            toolbarDivider
            toolbarButton("list.bullet", help: "箇条書き") { insertPrefix("- ") }
            toolbarButton("list.number", help: "番号付きリスト") { insertPrefix("1. ") }
            toolbarButton("chevron.left.forwardslash.chevron.right", help: "コード") { wrapSelection("`", "`") }
            toolbarDivider
            toolbarButton("textformat.size", help: "見出し") { insertPrefix("## ") }
            toolbarButton("minus", help: "水平線") { insertPrefix("\n---\n") }
            Spacer()
            Button {
                AppCommand.formatDocument.post()
            } label: {
                Label("整形", systemImage: "text.alignleft")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.kobaMute)
            .help("ドキュメント整形 (⌘⇧F)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.kobaSurface)
        .overlay(KobaHDivider(), alignment: .bottom)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.kobaLine.opacity(0.6))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 2)
    }

    private func toolbarButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.kobaMute)
        .help(help)
    }

    private func insertPrefix(_ prefix: String) {
        NotificationCenter.default.post(
            name: .insertSnippetAtCursor,
            object: nil,
            userInfo: ["text": prefix]
        )
    }

    private func wrapSelection(_ leading: String, _ trailing: String) {
        NotificationCenter.default.post(
            name: .insertSnippetAtCursor,
            object: nil,
            userInfo: ["text": "\(leading)\(trailing)"]
        )
    }
}