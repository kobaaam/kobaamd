import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

enum PreviewMode: String, CaseIterable {
    case split   = "Split"
    case wysiwyg = "WYSIWYG"
    case off     = "Off"
    case viewer  = "Viewer"
}

@Observable
@MainActor
final class AppViewModel {
    var selectedFileURL: URL? = nil {
        didSet {
            // アクティブタブの URL をすぐに反映してタブ名を更新する
            guard let id = activeTabID,
                  let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
            tabs[idx].url = selectedFileURL
        }
    }
    var editorText: String = ""
    var isDirty: Bool = false
    /// 最後に保存した時点の editorText。未保存の変更検知に使用。
    var savedText: String = ""
    @ObservationIgnored
    var previewScrollRatio: Double = 0
    var errorMessage: String? = nil
    var showError: Bool = false
    var previewMode: PreviewMode = .split
    var previousPreviewMode: PreviewMode = .split
    var isSidebarVisible: Bool = true
    var isFileLoading: Bool = false
    var isDiffMode: Bool = false
    var formatChangeCount: Int = 0
    var showFormatToast: Bool = false
    /// ファイルオープン完了後にエディタへ伝えるジャンプ先行番号
    var pendingJumpLine: Int? = nil

    // MARK: - Quick Insert
    let snippetStore = SnippetStore()
    var showQuickInsert: Bool = false

    let fileTreeViewModel = FileTreeViewModel()
    let quickOpenViewModel = QuickOpenViewModel()
    let outlineViewModel = OutlineViewModel()
    let backlinksViewModel = BacklinksViewModel()
    let todoViewModel = TodoViewModel()
    let tagsViewModel = TagsViewModel()
    let searchIndexService = WikiIndexService()

    // MARK: - Template Picker
    var showTemplatePicker: Bool = false
    private var formatToastTask: Task<Void, Never>? = nil

    init() {
        backlinksViewModel.appViewModel = self
    }

    func setPreviewScrollRatio(_ ratio: Double, source: String) {
        let clampedRatio = max(0, min(1, ratio))
        previewScrollRatio = clampedRatio
        NotificationCenter.default.post(
            name: .previewScrollRatioChanged,
            object: nil,
            userInfo: ["ratio": clampedRatio, "source": source]
        )
    }

    // MARK: - Tabs
    var tabs: [EditorTab] = []
    var activeTabID: UUID? = nil
    private var isRestoringEditorSession = false

    /// 現在アクティブなタブ。
    var activeTab: EditorTab? {
        tabs.first(where: { $0.id == activeTabID })
    }

    /// ファイルをタブで開く。既に開いていれば切り替えるだけ。
    func openInTab(url: URL, content: String) {
        isDiffMode = false
        if let existing = tabs.first(where: { $0.url == url }) {
            switchToTab(id: existing.id)
            return
        }
        flushActiveTab()
        let tab = EditorTab(url: url, content: content)
        tabs.append(tab)
        activate(tab: tab)
        if !isRestoringEditorSession {
            persistEditorSession()
        }
    }

    /// 開いているタブ一覧を UserDefaults に保存（dev リロード後に復元）。
    func persistEditorSession() {
        flushActiveTab()
        let urls = tabs.compactMap(\.url)
        AppState.saveEditorSession(tabURLs: urls, activeURL: activeTab?.url)
    }

    /// 前回のタブ構成を復元。タブが無い場合は lastFile にフォールバック。
    @MainActor
    func restoreEditorSession() async {
        let (tabURLs, activeURL) = AppState.loadEditorSession()
        if tabURLs.isEmpty {
            if let lastURL = AppState.loadLastFile(),
               FileManager.default.fileExists(atPath: lastURL.path) {
                await openFile(url: lastURL)
            }
            return
        }
        isRestoringEditorSession = true
        defer {
            isRestoringEditorSession = false
            persistEditorSession()
        }
        for url in tabURLs {
            await openFile(url: url)
        }
        if let activeURL,
           let tab = tabs.first(where: { $0.url == activeURL }) {
            switchToTab(id: tab.id)
        }
    }

    /// ワークスペース変更時（フォルダ追加・削除）に QuickOpen のインデックスを再構築する。
    func refreshQuickOpenIndex(forceSearchReindex: Bool = false) {
        quickOpenViewModel.indexFiles(
            from: fileTreeViewModel.folders,
            scopedTo: fileTreeViewModel.rootURL
        )
        quickOpenViewModel.filter()
        let folderURLs = fileTreeViewModel.folders.map(\.url)
        todoViewModel.updateWorkspaceRoots(folderURLs)
        // Folder スコープの対象は「最初に開いたワークスペースフォルダ」（PRD §2）
        todoViewModel.updateFolderRoot(folderURLs.first)
        tagsViewModel.updateWorkspaceRoots(folderURLs)
        searchIndexService.setRoot(folderURLs.first, force: forceSearchReindex)
    }

    @MainActor
    func openFile(url: URL) async {
        PerfLogger.begin("openFile(\(url.lastPathComponent))")
        defer { PerfLogger.end("openFile(\(url.lastPathComponent))") }
        guard FileService.supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
        do {
            PerfLogger.begin("openFile.readFile")
            let content = try await Task.detached(priority: .userInitiated) {
                try FileService().readFile(at: url)
            }.value
            PerfLogger.end("openFile.readFile")
            openInTab(url: url, content: content)
        } catch {
            showAppError(.fileReadFailed(url: url, underlying: error))
        }
    }

    /// ファイルを開き、エディタの準備完了後に指定行にジャンプする。
    /// エディタ側が .onChange(of: pendingJumpLine) で通知を受け取りジャンプする。
    @MainActor
    func openFileAndJump(url: URL, line: Int) async {
        await openFile(url: url)
        pendingJumpLine = line
    }

    /// 新規作成した成果物を開く（KMD-228）。`autoOpenNewArtifacts` が OFF のときは URL のみセット。
    @MainActor
    func openNewArtifact(url: URL) async {
        AppState.saveLastFile(url)
        guard AppState.shared.autoOpenNewArtifacts else {
            selectedFileURL = url
            editorText = ""
            markSaved()
            return
        }
        await openFile(url: url)
    }

    /// セッション切替時にエディタ・タブ・プレビュー状態をクリアする（KMD-224）。
    func resetEditorStateForSessionSwitch() {
        flushActiveTab()
        tabs = []
        activate(tab: nil)
        isDiffMode = false
        pendingJumpLine = nil
        outlineViewModel.update(text: "")
        backlinksViewModel.refresh(
            currentURL: nil,
            workspaceFolders: fileTreeViewModel.folders.map(\.url)
        )
    }

    /// 新しい空タブを追加する。
    func newTab() {
        isDiffMode = false
        flushActiveTab()
        let tab = EditorTab()
        tabs.append(tab)
        activate(tab: tab)
    }

    /// テンプレートの内容で新しいタブを開く。
    func newTabFromTemplate(content: String) {
        isDiffMode = false
        flushActiveTab()
        let tab = EditorTab(content: content)
        tabs.append(tab)
        activate(tab: tab)
        isDirty = true
    }

    /// タブを切り替える。
    func switchToTab(id: UUID) {
        isDiffMode = false
        guard id != activeTabID,
              let tab = tabs.first(where: { $0.id == id }) else { return }
        flushActiveTab()
        activate(tab: tab)
        if !isRestoringEditorSession {
            persistEditorSession()
        }
    }

    /// タブを閉じる。
    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        tabs.remove(at: idx)
        if wasActive {
            activate(tab: tabs.isEmpty ? nil : tabs[min(idx, tabs.count - 1)])
        }
        persistEditorSession()
    }

    /// アクティブタブの現在状態を保存する。
    func flushActiveTab() {
        guard let id = activeTabID,
              let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].content = editorText
        tabs[idx].isDirty = isDirty
        tabs[idx].url = selectedFileURL
    }

    /// バックグラウンドでファイルが書き換えられた場合に、開いているタブの in-memory コンテンツを同期する。
    /// アクティブタブの場合は editorText も更新する。
    func syncTabContent(url: URL, updated: String) {
        guard let idx = tabs.firstIndex(where: { $0.url == url }) else { return }
        tabs[idx].content = updated
        tabs[idx].isDirty = false
        if activeTabID == tabs[idx].id {
            editorText = updated
            savedText = updated
            isDirty = false
            outlineViewModel.update(text: updated)
            scheduleStatsUpdate()
            todoViewModel.update(text: updated)
            tagsViewModel.updateFile(url, text: updated)
        }
    }

    /// FSEvents 等でディスクが更新されたとき、未編集（!isDirty）の開いているタブをディスク内容に追従する。
    /// Claude Code 等の外部エージェントがファイルを書き換えた場合のプレビュー stale 対策。
    func syncOpenTabsFromDiskIfClean() {
        flushActiveTab()
        let fileService = FileService()
        for tab in tabs {
            guard let url = tab.url, !tab.isDirty else { continue }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let diskContent = try? fileService.readFile(at: url) else { continue }
            guard tab.content != diskContent else { continue }
            syncTabContent(url: url, updated: diskContent)
        }
    }

    // MARK: - Private Helpers

    /// エディタ状態をタブに同期する。nil を渡すとエディタをクリアする。
    private func activate(tab: EditorTab?) {
        PerfLogger.begin("AppViewModel.activate")
        defer { PerfLogger.end("AppViewModel.activate") }
        guard let tab else {
            activeTabID = nil
            editorText = ""
            selectedFileURL = nil
            isDirty = false
            savedText = ""
            outlineViewModel.update(text: "")
            backlinksViewModel.refresh(currentURL: nil, workspaceFolders: [])
            return
        }
        PerfLogger.event("AppViewModel.activate", "url=\(tab.url?.lastPathComponent ?? "nil") textLen=\(tab.content.count)")
        activeTabID = tab.id
        PerfLogger.begin("AppViewModel.activate.editorText=")
        editorText = tab.content
        PerfLogger.end("AppViewModel.activate.editorText=")
        selectedFileURL = tab.url
        isDirty = tab.isDirty
        savedText = tab.isDirty ? "" : tab.content
        PerfLogger.begin("AppViewModel.activate.outline.update")
        outlineViewModel.update(text: tab.content)
        PerfLogger.end("AppViewModel.activate.outline.update")
        PerfLogger.begin("AppViewModel.activate.backlinks.refresh")
        backlinksViewModel.refresh(
            currentURL: selectedFileURL,
            workspaceFolders: fileTreeViewModel.folders.map(\.url)
        )
        PerfLogger.end("AppViewModel.activate.backlinks.refresh")
    }

    // キャッシュ済みカウント — editorText 変更後に非同期で更新
    var lineCount: Int = 0
    var wordCount: Int = 0
    private var statsTask: Task<Void, Never>? = nil

    // MARK: - Save

    /// URL が確定済みならその場で保存。未保存なら saveAs シートを出す。
    /// View に依存しないよう AppViewModel に集約。
    func saveCurrentFile() {
        guard let url = selectedFileURL else {
            saveAs()
            return
        }
        do {
            try FileService().saveFile(at: url, content: editorText)
            markSaved()
        } catch {
            showAppError(.fileWriteFailed(url: url, underlying: error))
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        if let mdType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [mdType]
        }
        panel.nameFieldStringValue = "Untitled.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FileService().saveFile(at: url, content: editorText)
            selectedFileURL = url
            markSaved()
        } catch {
            showAppError(.fileWriteFailed(url: url, underlying: error))
        }
    }

    func toggleViewerMode() {
        let ext = selectedFileURL?.pathExtension.lowercased() ?? ""
        let isMD = ext == "md" || ext == "markdown" || ext.isEmpty
        guard isMD else { return }

        if previewMode == .viewer {
            previewMode = previousPreviewMode
        } else {
            previousPreviewMode = previewMode
            previewMode = .viewer
        }

        guard let window = NSApplication.shared.mainWindow else { return }
        let announcement = previewMode == .viewer ? "Reading mode active" : "Edit mode active"
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    func markSaved() {
        savedText = editorText
        isDirty = false
        scheduleStatsUpdate()
        todoViewModel.update(text: editorText)
        if todoViewModel.scope != .file, let url = selectedFileURL {
            todoViewModel.updateFile(url, text: editorText)
        }
        if let url = selectedFileURL {
            tagsViewModel.updateFile(url, text: editorText)
        }
    }

    func markEdited() {
        isDirty = true  // 編集時は即 true、保存時に false にする
        scheduleStatsUpdate()
    }

    private func scheduleStatsUpdate() {
        statsTask?.cancel()
        statsTask = Task.detached { [text = editorText] in
            guard !text.isEmpty else {
                await MainActor.run { [weak self] in
                    self?.lineCount = 0
                    self?.wordCount = 0
                }
                return
            }
            let lines = text.components(separatedBy: "\n").count
            let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
            await MainActor.run { [weak self] in
                self?.lineCount = lines
                self?.wordCount = words
            }
        }
    }

    func updateEditorText(_ text: String) {
        editorText = text
        markEdited()
        todoViewModel.update(text: text)
    }

    func formatCurrentDocument() {
        let formatted = MarkdownFormatterService().format(editorText)
        updateEditorText(formatted.result)
        formatChangeCount = formatted.changeCount
        showFormatToast = true

        formatToastTask?.cancel()
        formatToastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.showFormatToast = false
        }
    }

    func showAppError(_ error: AppError) {
        errorMessage = error.localizedDescription
        showError = true
    }

    /// NSItemProvider から URL を解決するヘルパー。View の重複を排除。
    func loadDroppedURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                switch item {
                case let data as Data:
                    url = URL(dataRepresentation: data, relativeTo: nil)
                case let droppedURL as URL:
                    url = droppedURL
                case let string as String:
                    url = URL(string: string)
                default:
                    url = nil
                }
                continuation.resume(returning: url)
            }
        }
    }

    /// ドロップされた URL をタブで開く。エラー時は showAppError を呼ぶ。
    @MainActor
    func openDroppedFile(url: URL) async {
        // ディレクトリはサイドバーに追加
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            fileTreeViewModel.addFolder(url: url)
            return
        }
        guard FileService.supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
        do {
            let content = try await Task.detached(priority: .userInitiated) { try FileService().readFile(at: url) }.value
            openInTab(url: url, content: content)
        } catch {
            showAppError(.fileReadFailed(url: url, underlying: error))
        }
    }

    // MARK: - Quick Insert
    func insertSnippet(_ prompt: String) {
        let text = "{{\(prompt)}}"
        NotificationCenter.default.post(
            name: .insertSnippetAtCursor,
            object: nil,
            userInfo: ["text": text]
        )
        showQuickInsert = false
    }

    // MARK: - PDF Export

    var isPDFExporting: Bool = false
    var pdfStatusMessage: String? = nil
    private var pdfStatusTask: Task<Void, Never>? = nil

    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let defaultName: String
        if let url = selectedFileURL {
            defaultName = url.deletingPathExtension().lastPathComponent + ".pdf"
        } else {
            defaultName = "Untitled.pdf"
        }
        panel.nameFieldStringValue = defaultName
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isPDFExporting = true
        pdfStatusMessage = "PDF生成中..."

        NotificationCenter.default.post(
            name: .exportPDFWithURL,
            object: url
        )
    }

    func handlePDFExportResult(_ result: Result<Void, Error>) {
        isPDFExporting = false
        pdfStatusTask?.cancel()
        switch result {
        case .success:
            pdfStatusMessage = "PDFを書き出しました"
            pdfStatusTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.pdfStatusMessage = nil
            }
        case .failure(let error):
            pdfStatusMessage = nil
            showAppError(.fileWriteFailed(url: URL(fileURLWithPath: ""), underlying: error))
        }
    }

}
