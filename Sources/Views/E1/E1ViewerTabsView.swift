import AppKit
import SwiftUI

// MARK: - E1 right pane viewer (Re-concept MD-first layout)

struct E1ViewerTabsView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable private var appState = AppState.shared
    @State private var selectedTab: E1ViewerTab = .rendered
    @State private var markdownMode: E1MarkdownViewMode = .split
    @State private var mdSplitFraction: CGFloat = E1ViewerTabsView.loadMdSplitFraction()

    private let mdSplitMin: CGFloat = 0.25
    private let mdSplitMax: CGFloat = 0.75
    private let mdSplitDividerHit: CGFloat = 10

    private var fileKind: E1FileKind {
        E1ViewerLayoutPolicy.fileKind(for: appViewModel.selectedFileURL)
    }

    var body: some View {
        let chrome = appState.selectedTheme
        VStack(spacing: 0) {
            tabBar
            if fileKind == .markdown, appViewModel.selectedFileURL != nil {
                E1MarkdownToolbar()
            }
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if fileKind == .markdown, appViewModel.selectedFileURL != nil {
                E1EditorStatusBar()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.chromeSurface)
        .onChange(of: appViewModel.selectedFileURL) { _, _ in
            syncToFileType()
        }
        .onAppear {
            syncToFileType()
        }
        .onChange(of: mdSplitFraction) { _, newValue in
            Self.saveMdSplitFraction(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .e1ToggleMdSplitRequested)) { _ in
            if fileKind == .markdown {
                markdownMode = markdownMode == .split ? .editor : .split
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .e1FocusViewerRequested)) { _ in
            focusViewerEditor()
        }
    }

    private var tabBar: some View {
        let chrome = appState.selectedTheme
        return HStack(spacing: 0) {
            if fileKind == .markdown {
                markdownModePicker(chrome: chrome)
            } else {
                ForEach(E1ViewerLayoutPolicy.visibleTabs(for: fileKind)) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: isTabHighlighted(tab) ? .semibold : .regular))
                            .foregroundStyle(isTabHighlighted(tab) ? chrome.chromeSelectedInk : chrome.chromeInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isTabHighlighted(tab) ? chrome.chromeSelection : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            if fileKind == .markdown {
                Button("Diff") {
                    selectedTab = .diff
                    markdownMode = .editor
                }
                .font(.system(size: 10, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == .diff ? chrome.chromeInk : chrome.chromeMute2)
                .help("差分ビュー")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(chrome.chromeSurface)
        .overlay(KobaHDivider(), alignment: .bottom)
    }

    @ViewBuilder
    private var tabContent: some View {
        let chrome = appState.selectedTheme
        if appViewModel.selectedFileURL == nil {
            viewerEmptyState
        } else if selectedTab == .diff {
            DiffInlineView(
                preloadText: appViewModel.editorText,
                preloadFileName: appViewModel.selectedFileURL?.lastPathComponent ?? "Untitled"
            )
            .background(chrome.chromePaper)
        } else if fileKind == .markdown {
            markdownPane
        } else {
            exclusiveTabContent
        }
    }

    @ViewBuilder
    private var markdownPane: some View {
        let chrome = appState.selectedTheme
        switch markdownMode {
        case .split:
            markdownHorizontalSplit
        case .editor:
            EditorView()
                .background(chrome.chromePaper)
        case .preview:
            PreviewView()
                .background(chrome.chromePaper)
        }
    }

    private var markdownHorizontalSplit: some View {
        let chrome = appState.selectedTheme
        return GeometryReader { geo in
            let minLeft = geo.size.width * mdSplitMin
            let maxLeft = geo.size.width * mdSplitMax
            let leftWidth = min(maxLeft, max(minLeft, geo.size.width * mdSplitFraction))

            HStack(spacing: 0) {
                EditorView()
                    .frame(width: leftWidth)
                    .frame(maxHeight: .infinity)
                    .background(chrome.chromePaper)
                    .clipped()

                E1WidthDivider(
                    width: Binding(
                        get: { leftWidth },
                        set: { newWidth in
                            mdSplitFraction = newWidth / max(geo.size.width, 1)
                        }
                    ),
                    minWidth: minLeft,
                    maxWidth: maxLeft,
                    hitWidth: mdSplitDividerHit,
                    dragAxis: .growOnDragRight
                )

                PreviewView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(chrome.chromePaper)
                    .clipped()
            }
        }
    }

    @ViewBuilder
    private var exclusiveTabContent: some View {
        let chrome = appState.selectedTheme
        switch selectedTab {
        case .rendered:
            switch fileKind {
            case .markdown:
                PreviewView()
                    .background(chrome.chromePaper)
            case .html:
                HTMLPreviewView()
            default:
                tabMismatchHint("プレビューに対応していないファイルです")
            }
        case .source:
            EditorView()
                .background(chrome.chromePaper)
        case .d2:
            if fileKind == .d2 {
                D2PreviewView()
                    .background(chrome.chromePaper)
            } else {
                tabMismatchHint(".d2 ファイルを選択してください")
            }
        case .csv:
            if fileKind == .csv {
                CSVPreviewView()
                    .background(chrome.chromePaper)
            } else {
                tabMismatchHint(".csv ファイルを選択してください")
            }
        case .diff:
            EmptyView()
        }
    }

    private var viewerEmptyState: some View {
        let chrome = appState.selectedTheme
        return VStack(spacing: 10) {
            Spacer()
            Image(systemName: "doc.richtext")
                .font(.system(size: 28))
                .foregroundStyle(chrome.chromeMute)
            Text("ファイルを選択してください")
                .font(.system(size: 12))
                .foregroundStyle(chrome.chromeMute)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.chromePaper)
    }

    private func tabMismatchHint(_ message: String) -> some View {
        let chrome = appState.selectedTheme
        return VStack {
            Spacer()
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(chrome.chromeMute)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chrome.chromePaper)
    }

    private func isTabEnabled(_ tab: E1ViewerTab) -> Bool {
        E1ViewerLayoutPolicy.isTabEnabled(tab, kind: fileKind)
    }

    private func isTabHighlighted(_ tab: E1ViewerTab) -> Bool {
        selectedTab == tab
    }

    private func syncToFileType() {
        selectedTab = E1ViewerLayoutPolicy.defaultTab(for: fileKind)
        markdownMode = E1ViewerLayoutPolicy.defaultMarkdownMode(for: fileKind)
    }

    private func markdownModePicker(chrome: ColorTheme) -> some View {
        HStack(spacing: 2) {
            ForEach(E1MarkdownViewMode.allCases) { mode in
                let isSelected = markdownMode == mode && selectedTab != .diff
                Button {
                    markdownMode = mode
                    if selectedTab == .diff {
                        selectedTab = .rendered
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? chrome.chromeSelectedInk : chrome.chromeInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? chrome.chromeSelection : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(chrome.chromePaper.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(chrome.chromeLine.opacity(0.5), lineWidth: 1)
        )
        .frame(maxWidth: 240)
        .accessibilityLabel("表示モード")
    }

    private func focusViewerEditor() {
        if fileKind == .markdown {
            markdownMode = .editor
        } else {
            selectedTab = .source
        }
        NotificationCenter.default.post(name: .e1FocusEditorRequested, object: nil)
    }

    private static let mdSplitFractionKey = "e1ViewerMdSplitFraction"

    private static func loadMdSplitFraction() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: mdSplitFractionKey)
        if stored > 0 { return CGFloat(stored) }
        return E1ViewerLayoutPolicy.defaultMdSplitFraction
    }

    private static func saveMdSplitFraction(_ value: CGFloat) {
        UserDefaults.standard.set(Double(value), forKey: mdSplitFractionKey)
    }
}