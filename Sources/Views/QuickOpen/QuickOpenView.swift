import SwiftUI

// MARK: - QuickOpenView

struct QuickOpenView: View {
    @State var viewModel: QuickOpenViewModel
    let onSelect: (URL) -> Void
    let onDismiss: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.kobaMute)
                    .font(.system(size: 14))
                TextField("ファイルを検索... (⌘P)", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isTextFieldFocused)
                    .onKeyPress(.downArrow) {
                        viewModel.selectNext()
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        viewModel.selectPrev()
                        return .handled
                    }
                    .onKeyPress(.return) {
                        if let item = viewModel.selectedItem {
                            onSelect(item.url)
                        }
                        return .handled
                    }
                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.kobaMute)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .foregroundStyle(Color.kobaLine)

            // Candidates list
            if viewModel.candidates.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.candidates.enumerated()), id: \.element.id) { index, item in
                                candidateRow(item: item, index: index)
                                    .id(index)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .onChange(of: viewModel.selectedIndex) { _, newIndex in
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 6)
        .onChange(of: viewModel.query) { _, _ in
            viewModel.filter()
        }
        .onExitCommand {
            onDismiss()
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }

    // MARK: - Candidate row

    private func candidateRow(item: QuickOpenViewModel.QuickOpenItem, index: Int) -> some View {
        let isSelected = index == viewModel.selectedIndex
        return Button {
            onSelect(item.url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: item.url))
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.white : Color.kobaMute)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.fileName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.kobaInk)
                        .lineLimit(1)
                    Text(item.relativePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.kobaMute2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isSelected ? Color.kobaAccent : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                viewModel.selectedIndex = index
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            if viewModel.query.isEmpty {
                Text("ワークスペースにフォルダを追加してください")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kobaMute)
                Text("⌘O でフォルダを開く")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.kobaMute2)
            } else {
                Text("「\(viewModel.query)」に一致するファイルが見つかりません")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kobaMute)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Icon helper

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return "doc.text"
        case "swift":          return "swift"
        case "json", "yaml", "yml", "toml": return "curlybraces"
        case "html", "css", "scss", "xml": return "globe"
        case "sh", "zsh", "bash": return "terminal"
        case "py":             return "doc.text.below.echelon"
        default:               return "doc"
        }
    }
}
