import AppKit
import SwiftUI

// MARK: - E1 right pane viewer tabs (KMD-227, KMD-235 split)

enum E1ViewerTab: String, CaseIterable, Identifiable {
    case rendered = "Rendered"
    case source = "Source"
    case d2 = "D2"
    case diff = "Diff"
    case csv = "CSV"

    var id: String { rawValue }

    /// Rendered + Source share one split pane for Markdown.
    var isMarkdownPane: Bool {
        self == .rendered || self == .source
    }
}

struct E1ViewerTabsView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var selectedTab: E1ViewerTab = .rendered
    @State private var mdSplitFraction: CGFloat = E1ViewerTabsView.loadMdSplitFraction()

    private let mdSplitMin: CGFloat = 0.25
    private let mdSplitMax: CGFloat = 0.75
    private let mdSplitDividerHit: CGFloat = 10

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
        .onChange(of: mdSplitFraction) { _, newValue in
            Self.saveMdSplitFraction(newValue)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(E1ViewerTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 10, weight: isTabHighlighted(tab) ? .semibold : .regular))
                        .foregroundStyle(isTabHighlighted(tab) ? Color.white : Color.kobaMute)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isTabHighlighted(tab) ? Color.kobaInk : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .disabled(!isTabEnabled(tab))
                .opacity(isTabEnabled(tab) ? 1 : 0.4)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(isTabHighlighted(tab) ? .isSelected : [])
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
        } else if usesMarkdownSplit {
            markdownSplitPane
        } else {
            exclusiveTabContent
        }
    }

    /// Phase 2a: Rendered (top) + Source (bottom) for Markdown.
    private var markdownSplitPane: some View {
        GeometryReader { geo in
            let minTop = geo.size.height * mdSplitMin
            let maxTop = geo.size.height * mdSplitMax
            let topHeight = min(maxTop, max(minTop, geo.size.height * mdSplitFraction))

            VStack(spacing: 0) {
                PreviewView()
                    .frame(height: topHeight)
                    .frame(maxWidth: .infinity)
                    .background(Color.kobaSurface)
                    .clipped()

                E1HeightDivider(
                    fraction: $mdSplitFraction,
                    availableHeight: geo.size.height,
                    minFraction: mdSplitMin,
                    maxFraction: mdSplitMax,
                    hitHeight: mdSplitDividerHit
                )

                EditorView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.kobaPaper)
            }
        }
    }

    @ViewBuilder
    private var exclusiveTabContent: some View {
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

    private var usesMarkdownSplit: Bool {
        isMDFile && selectedTab.isMarkdownPane
    }

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

    private func isTabHighlighted(_ tab: E1ViewerTab) -> Bool {
        if usesMarkdownSplit, tab.isMarkdownPane {
            return true
        }
        return selectedTab == tab
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

    private static let mdSplitFractionKey = "e1ViewerMdSplitFraction"
    private static let defaultMdSplitFraction: CGFloat = 0.45

    private static func loadMdSplitFraction() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: mdSplitFractionKey)
        if stored > 0 { return CGFloat(stored) }
        return defaultMdSplitFraction
    }

    private static func saveMdSplitFraction(_ value: CGFloat) {
        UserDefaults.standard.set(Double(value), forKey: mdSplitFractionKey)
    }
}

// MARK: - Vertical split divider (KMD-235)

struct E1HeightDivider: View {
    @Binding var fraction: CGFloat
    let availableHeight: CGFloat
    let minFraction: CGFloat
    let maxFraction: CGFloat
    let hitHeight: CGFloat
    @State private var baseFraction: CGFloat = 0
    @State private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            if isHovering || isDragging {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.kobaAccent.opacity(0.12))
                    .padding(.horizontal, 8)
            }
            KobaHDivider()
        }
        .frame(height: hitHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        baseFraction = fraction
                    }
                    let delta = value.translation.height / max(availableHeight, 1)
                    fraction = min(maxFraction, max(minFraction, baseFraction + delta))
                }
                .onEnded { _ in isDragging = false }
        )
        .onHover { inside in
            isHovering = inside
            if inside { NSCursor.resizeUpDown.push() }
            else { NSCursor.pop() }
        }
        .accessibilityLabel("プレビューとエディタの境界を調整")
        .help("ドラッグして上下の比率を変更")
    }
}