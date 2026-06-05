import SwiftUI

// MARK: - E1 right pane viewer tabs (KMD-227)

enum E1ViewerTab: String, CaseIterable, Identifiable {
    case rendered = "Rendered"
    case source = "Source"
    case d2 = "D2"
    case diff = "Diff"
    case csv = "CSV"

    var id: String { rawValue }
}

struct E1ViewerTabsView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var selectedTab: E1ViewerTab = .rendered

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kobaSurface)
        .onChange(of: appViewModel.selectedFileURL) { _, _ in
            syncTabToFileType()
        }
        .onAppear {
            syncTabToFileType()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(E1ViewerTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.kobaMute)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selectedTab == tab ? Color.kobaInk : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .disabled(!isTabEnabled(tab))
                .opacity(isTabEnabled(tab) ? 1 : 0.4)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.kobaSurface)
        .overlay(KobaHDivider(), alignment: .bottom)
    }

    @ViewBuilder
    private var tabContent: some View {
        if appViewModel.selectedFileURL == nil {
            viewerEmptyState
        } else {
            switch selectedTab {
            case .rendered:
                if isMDFile {
                    PreviewView()
                        .background(Color.kobaSurface)
                } else {
                    tabMismatchHint("Markdown ファイルを開くとプレビューが表示されます")
                }
            case .source:
                EditorView()
                    .background(Color.kobaPaper)
            case .d2:
                if isD2File {
                    D2PreviewView()
                        .background(Color.kobaSurface)
                } else {
                    tabMismatchHint(".d2 ファイルを選択してください")
                }
            case .csv:
                if isCSVFile {
                    CSVPreviewView()
                        .background(Color.kobaSurface)
                } else {
                    tabMismatchHint(".csv ファイルを選択してください")
                }
            case .diff:
                DiffInlineView(
                    preloadText: appViewModel.editorText,
                    preloadFileName: appViewModel.selectedFileURL?.lastPathComponent ?? "Untitled"
                )
                .background(Color.kobaPaper)
            }
        }
    }

    private var viewerEmptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "doc.richtext")
                .font(.system(size: 28))
                .foregroundStyle(Color.kobaMute)
            Text("ファイルを選択してください")
                .font(.system(size: 12))
                .foregroundStyle(Color.kobaMute)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kobaPaper)
    }

    private func tabMismatchHint(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.kobaMute)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kobaPaper)
    }

    private var fileExtension: String {
        appViewModel.selectedFileURL?.pathExtension.lowercased() ?? ""
    }

    private var isMDFile: Bool {
        let ext = fileExtension
        return ext == "md" || ext == "markdown" || ext.isEmpty
    }

    private var isD2File: Bool { fileExtension == "d2" }
    private var isCSVFile: Bool { fileExtension == "csv" }

    private func isTabEnabled(_ tab: E1ViewerTab) -> Bool {
        guard appViewModel.selectedFileURL != nil else {
            return tab == .source
        }
        switch tab {
        case .rendered: return isMDFile
        case .source: return true
        case .d2: return isD2File
        case .csv: return isCSVFile
        case .diff: return true
        }
    }

    private func syncTabToFileType() {
        guard appViewModel.selectedFileURL != nil else {
            selectedTab = .source
            return
        }
        if isCSVFile {
            selectedTab = .csv
        } else if isD2File {
            selectedTab = .d2
        } else if isMDFile {
            selectedTab = .rendered
        } else {
            selectedTab = .source
        }
    }
}