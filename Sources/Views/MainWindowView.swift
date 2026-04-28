import SwiftUI

// MARK: - Main window

struct MainWindowView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var splitFraction: CGFloat = 0.55
    @State private var isDiffSheetPresented: Bool = false
    @State private var diffInitialText: String = ""
    @State private var diffInitialFileName: String = ""
    @State private var isWindowDragTargeted: Bool = false
    @State private var isQuickOpenPresented: Bool = false
    @State private var isChatSidebarVisible: Bool = false

    private var isMDFile: Bool {
        let ext = appViewModel.selectedFileURL?.pathExtension.lowercased() ?? ""
        return ext == "md" || ext == "markdown" || ext.isEmpty
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        @Bindable var vm = appViewModel

        ToolbarItemGroup(placement: .navigation) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("サイドバーの表示/非表示 (⌘B)")

            Button {
                NotificationCenter.default.post(name: .openFolderRequested, object: nil)
            } label: {
                Image(systemName: "folder")
            }
            .help("Open Folder (⌘O)")
        }

        // Center: preview mode selector (only when a file is open)
        ToolbarItem(placement: .principal) {
            if vm.selectedFileURL != nil {
                Picker("", selection: $vm.previewMode) {
                    Image(systemName: "pencil").tag(PreviewMode.off)
                    Image(systemName: "rectangle.split.2x1").tag(PreviewMode.split)
                    if isMDFile {
                        Image(systemName: "eye").tag(PreviewMode.wysiwyg)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .help("プレビューモード切り替え")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                NotificationCenter.default.post(name: .newFileRequested, object: nil)
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help("New File (⌘N)")

            // Save button doubles as autosave indicator
            Button {
                NotificationCenter.default.post(name: .saveRequested, object: nil)
            } label: {
                Image(systemName: vm.isDirty ? "circle.fill" : "checkmark.circle")
                    .foregroundStyle(vm.isDirty ? Color.kobaAccent : .secondary)
            }
            .help("Save (⌘S)")

            Divider()

            Button {
                NotificationCenter.default.post(name: .findRequested, object: nil)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Find & Replace (⌘F)")

            Button {
                NotificationCenter.default.post(name: .aiAssistRequested, object: nil)
            } label: {
                Image(systemName: "sparkles")
            }
            .help("AI アシスト (⌘E)")

            Button {
                NotificationCenter.default.post(name: .aiChatRequested, object: nil)
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
            }
            .help("AI チャット (⌘⇧E)")

            Button {
                diffInitialText = appViewModel.activeTab?.content ?? ""
                diffInitialFileName = appViewModel.activeTab?.title ?? ""
                isDiffSheetPresented = true
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("Diff ビュー (⌘D)")
        }
    }

    var body: some View {
        @Bindable var vm = appViewModel
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // ── Main pane ──────────────────────────────────────────
                HStack(spacing: 0) {
                    if appViewModel.isSidebarVisible {
                        SidebarView()
                            .frame(width: 240)
                            .transition(.move(edge: .leading))

                        KobaDivider()
                    }

                    VStack(spacing: 0) {
                        TabBarView()

                        if appViewModel.isDiffMode {
                            DiffInlineView(preloadText: appViewModel.activeTab?.content ?? "",
                                           preloadFileName: appViewModel.activeTab?.title ?? "")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if appViewModel.previewMode == .wysiwyg {
                            @Bindable var vm = appViewModel
                            WYSIWYGEditorView(text: $vm.editorText)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.kobaPaper)
                        } else if appViewModel.previewMode == .split {
                            GeometryReader { geo in
                                HStack(spacing: 0) {
                                    EditorView()
                                        .frame(width: max(280, geo.size.width * splitFraction))
                                        .background(Color.kobaPaper)
                                    SplitDivider(fraction: $splitFraction, availableWidth: geo.size.width)
                                    PreviewView()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.kobaSurface)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            EditorView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.kobaPaper)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isChatSidebarVisible {
                        KobaDivider()
                        AIChatView(
                            viewModel: appViewModel.aIChatViewModel,
                            onInsertToEditor: { text in
                                appViewModel.editorText += "\n\n" + text
                            }
                        )
                        .frame(width: 320)
                        .transition(.move(edge: .trailing))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.2), value: appViewModel.isSidebarVisible)
                .animation(.easeInOut(duration: 0.2), value: isChatSidebarVisible)
                .overlay {
                    if isWindowDragTargeted {
                        ZStack {
                            Color.kobaAccent
                                .opacity(0.04)
                                .allowsHitTesting(false)

                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    Color.kobaAccent,
                                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                                )
                                .padding(10)
                                .allowsHitTesting(false)

                            Text("Drop to open")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.kobaAccent.opacity(0.7))
                                .allowsHitTesting(false)
                        }
                    }
                }

                // ── Status / command bar ───────────────────────────────
                StatusCommandBar(
                    previewMode: $vm.previewMode,
                    isMDFile: isMDFile,
                    confluenceSyncMessage: appViewModel.confluenceSyncViewModel.syncStatusMessage,
                    isConfluenceSyncing: appViewModel.confluenceSyncViewModel.isSyncing
                )
            }

            if appViewModel.showFormatToast {
                Text("\(appViewModel.formatChangeCount) changes applied")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 42)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isWindowDragTargeted, perform: handleDrop(providers:))
        .overlay(alignment: .top) {
            if isQuickOpenPresented {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { isQuickOpenPresented = false }
                    QuickOpenView(
                        viewModel: appViewModel.quickOpenViewModel,
                        onSelect: { url in
                            isQuickOpenPresented = false
                            Task {
                                await appViewModel.openFile(url: url)
                            }
                        },
                        onDismiss: { isQuickOpenPresented = false }
                    )
                    .padding(.top, 44)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear {
            isChatSidebarVisible = appViewModel.isChatSidebarVisible
        }
        .modifier(
            MainWindowCommandReceiver(
                appViewModel: appViewModel,
                isDiffSheetPresented: $isDiffSheetPresented,
                diffInitialText: $diffInitialText,
                diffInitialFileName: $diffInitialFileName,
                isQuickOpenPresented: $isQuickOpenPresented,
                isChatSidebarVisible: $isChatSidebarVisible
            )
        )
        .navigationTitle(appViewModel.selectedFileURL?.lastPathComponent ?? "kobaamd")
        .background(Color.kobaPaper)
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task {
            for provider in providers {
                guard let url = await appViewModel.loadDroppedURL(from: provider) else { continue }
                await appViewModel.openDroppedFile(url: url)
            }
        }
        return true
    }
}

extension MainWindowView {
    struct MainWindowCommandReceiver: ViewModifier {
        let appViewModel: AppViewModel
        @Binding var isDiffSheetPresented: Bool
        @Binding var diffInitialText: String
        @Binding var diffInitialFileName: String
        @Binding var isQuickOpenPresented: Bool
        @Binding var isChatSidebarVisible: Bool

        func body(content: Content) -> some View {
            content
                .onReceive(NotificationCenter.default.publisher(for: .quickOpenRequested)) { _ in
                    appViewModel.quickOpenViewModel.query = ""
                    appViewModel.quickOpenViewModel.filter()
                    isQuickOpenPresented = true
                }
                .onChange(of: appViewModel.selectedFileURL) { _, url in
                    let ext = url?.pathExtension.lowercased() ?? ""
                    let isMD = ext == "md" || ext == "markdown" || ext.isEmpty
                    if !isMD && appViewModel.previewMode == .wysiwyg {
                        appViewModel.previewMode = .split
                    }
                }
                .onChange(of: appViewModel.fileTreeViewModel.folders) { _, _ in
                    appViewModel.refreshQuickOpenIndex()
                }
                .onChange(of: AppState.shared.pendingOpenFileURL) { _, fileURL in
                    guard let url = fileURL else { return }
                    AppState.shared.pendingOpenFileURL = nil
                    Task {
                        await appViewModel.openFile(url: url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .saveRequested)) { _ in
                    if AppState.shared.autoFormatOnSave {
                        appViewModel.formatCurrentDocument()
                    }
                    appViewModel.saveCurrentFile()
                }
                .onReceive(NotificationCenter.default.publisher(for: .formatDocumentRequested)) { _ in
                    appViewModel.formatCurrentDocument()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openFolderRequested)) { _ in
                    appViewModel.fileTreeViewModel.addFolder()
                }
                .onReceive(NotificationCenter.default.publisher(for: .newTabRequested)) { _ in
                    appViewModel.newTab()
                }
                .modifier(MainWindowCommandReceiverPart2(
                    appViewModel: appViewModel,
                    isDiffSheetPresented: $isDiffSheetPresented,
                    confluenceSheetPresented: Bindable(appViewModel.confluenceSyncViewModel).isPageSettingSheetPresented
                ))
                .onReceive(NotificationCenter.default.publisher(for: .cancelAIGenerationRequested)) { _ in
                    appViewModel.cancelAIGeneration()
                }
                .onReceive(NotificationCenter.default.publisher(for: .aiChatRequested)) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isChatSidebarVisible.toggle()
                        appViewModel.isChatSidebarVisible = isChatSidebarVisible
                    }
                }
        }
    }
}

// MARK: - Command receiver part 2 (sheets + secondary commands)

private struct MainWindowCommandReceiverPart2: ViewModifier {
    let appViewModel: AppViewModel
    @Binding var isDiffSheetPresented: Bool
    @Binding var confluenceSheetPresented: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .sidebarToggleRequested)) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    appViewModel.isSidebarVisible.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportPDFRequested)) { _ in
                appViewModel.exportPDF()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportPDFCompleted)) { note in
                if let result = note.object as? Result<Void, Error> {
                    appViewModel.handlePDFExportResult(result)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .confluenceSyncRequested)) { _ in
                appViewModel.syncToConfluence()
            }
            .onReceive(NotificationCenter.default.publisher(for: .confluencePageSettingsRequested)) { _ in
                appViewModel.confluenceSyncViewModel.currentFileURL = appViewModel.selectedFileURL
                appViewModel.confluenceSyncViewModel.isPageSettingSheetPresented = true
            }
            .sheet(isPresented: $isDiffSheetPresented) {
                DiffSheetView(preloadText: appViewModel.activeTab?.content ?? "",
                              preloadFileName: appViewModel.activeTab?.title ?? "")
            }
            .sheet(isPresented: $confluenceSheetPresented) {
                if let url = appViewModel.confluenceSyncViewModel.currentFileURL {
                    ConfluencePageSettingSheet(fileURL: url)
                        .environment(appViewModel.confluenceSyncViewModel)
                }
            }
    }
}

// MARK: - Status / command bar

struct StatusCommandBar: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Binding var previewMode: PreviewMode
    var isMDFile: Bool = true
    var confluenceSyncMessage: String? = nil
    var isConfluenceSyncing: Bool = false

    var filePath: String {
        guard let url = appViewModel.selectedFileURL else { return "" }
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? url.lastPathComponent : "\(parent) / \(url.lastPathComponent)"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left — breadcrumb + line count
            HStack(spacing: 8) {
                if !filePath.isEmpty {
                    Text(filePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.kobaMute)
                    if appViewModel.isDirty {
                        Circle()
                            .fill(Color.kobaAccent)
                            .frame(width: 5, height: 5)
                    }
                    kobaLineSep()
                }
                if appViewModel.lineCount > 0 {
                    Text("\(appViewModel.lineCount) lines")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.kobaMute2)
                    kobaLineSep()
                    Text("\(appViewModel.wordCount) words")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.kobaMute2)
                }
            }
            .padding(.leading, 14)

            Spacer()

            // AI生成ステータス
            if appViewModel.isAIGenerating {
                HStack(spacing: 4) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                    Text("AI生成中... ⌘. でキャンセル")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.kobaMute)
                }
                .padding(.horizontal, 8)
            }

            // PDF書き出しステータス
            if let msg = appViewModel.pdfStatusMessage {
                HStack(spacing: 4) {
                    if appViewModel.isPDFExporting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                    }
                    Text(msg)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.kobaMute)
                }
                .padding(.horizontal, 8)
            }

            // Confluence 同期ステータス
            if let msg = confluenceSyncMessage {
                HStack(spacing: 4) {
                    if isConfluenceSyncing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                    }
                    Text(msg)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.kobaMute)
                }
                .padding(.horizontal, 8)
            }

            // Right — version + preview toggle + keyboard hints
            HStack(spacing: 14) {
                Text(AppVersion.display)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.kobaMute2)

                kobaLineSep()
                // Preview toggle
                HStack(spacing: 0) {
                    ForEach(PreviewMode.allCases.filter { isMDFile || $0 != .wysiwyg }, id: \.self) { mode in
                        Button {
                            previewMode = mode
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(previewMode == mode ? Color.white : Color.kobaMute)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(previewMode == mode ? Color.kobaInk : Color.clear)
                        }
                        .buttonStyle(.plain)
                        .help(helpText(for: mode))
                    }
                }
                .background(Color.kobaLine.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.kobaLine, lineWidth: 1)
                )

                kobaLineSep()

                KbdHint(key: "⌘F", label: "Find")
                KbdHint(key: "⌘S", label: "Save")
            }
            .padding(.trailing, 14)
        }
        .frame(height: 30)
        .background(Color.kobaSurface)
        .overlay(KobaHDivider(), alignment: .top)
    }

    func kobaLineSep() -> some View {
        Rectangle()
            .fill(Color.kobaLine)
            .frame(width: 1, height: 12)
    }

    func helpText(for mode: PreviewMode) -> String {
        switch mode {
        case .off:     return "エディタのみ表示"
        case .split:   return "エディタ + プレビューを並べて表示"
        case .wysiwyg: return "リアルタイムプレビュー（WYSIWYG）"
        }
    }
}

// MARK: - Small shared components

struct KobaDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.kobaLine)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}

/// 水平方向の 1px セパレーター（StatusCommandBar 上部など横線に使う）
struct KobaHDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.kobaLine)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Draggable split divider

struct SplitDivider: View {
    @Binding var fraction: CGFloat
    let availableWidth: CGFloat
    @State private var baseF: CGFloat = 0
    @State private var isDragging: Bool = false

    var body: some View {
        Color.kobaLine
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        if !isDragging {
                            isDragging = true
                            baseF = fraction
                        }
                        let newF = baseF + v.translation.width / availableWidth
                        fraction = min(0.8, max(0.2, newF))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
    }
}

struct KbdHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.kobaMute)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.kobaSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.kobaLine, lineWidth: 1)
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.kobaMute2)
        }
    }
}
