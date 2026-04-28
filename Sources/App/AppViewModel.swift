import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

enum PreviewMode: String, CaseIterable {
    case split   = "Split"
    case wysiwyg = "WYSIWYG"
    case off     = "Off"
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
    var previewScrollRatio: Double = 0
    var errorMessage: String? = nil
    var showError: Bool = false
    var previewMode: PreviewMode = .split
    var isSidebarVisible: Bool = true
    var isFileLoading: Bool = false
    var isDiffMode: Bool = false
    var formatChangeCount: Int = 0
    var showFormatToast: Bool = false
    /// AI インライン補完のストリーミング中を示すフラグ。ステータスバー表示に使用。
    var isAIGenerating: Bool = false

    // MARK: - Quick Insert
    let snippetStore = SnippetStore()
    var showQuickInsert: Bool = false

    let fileTreeViewModel = FileTreeViewModel()
    let quickOpenViewModel = QuickOpenViewModel()
    let outlineViewModel = OutlineViewModel()
    let todoViewModel = TodoViewModel()
    let confluenceSyncViewModel = ConfluenceSyncViewModel()
    private var formatToastTask: Task<Void, Never>? = nil
    /// AI インライン補完のアクティブタスク。キャンセル用。
    private var aiTask: Task<Void, Never>? = nil
    /// AIService の注入ポイント（テスト時はモックを渡す）。
    private let aiService: AIServiceProtocol

    init(aiService: AIServiceProtocol = AIService()) {
        self.aiService = aiService
    }

    // MARK: - Tabs
    var tabs: [EditorTab] = []
    var activeTabID: UUID? = nil

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
    }

    /// ワークスペース変更時（フォルダ追加・削除）に QuickOpen のインデックスを再構築する。
    func refreshQuickOpenIndex() {
        quickOpenViewModel.indexFiles(from: fileTreeViewModel.folders)
        quickOpenViewModel.filter()
    }

    @MainActor
    func openFile(url: URL) async {
        guard FileService.supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
        do {
            let content = try await Task.detached(priority: .userInitiated) {
                try FileService().readFile(at: url)
            }.value
            openInTab(url: url, content: content)
        } catch {
            showAppError(.fileReadFailed(url: url, underlying: error))
        }
    }

    /// 新しい空タブを追加する。
    func newTab() {
        isDiffMode = false
        flushActiveTab()
        let tab = EditorTab()
        tabs.append(tab)
        activate(tab: tab)
    }

    /// タブを切り替える。
    func switchToTab(id: UUID) {
        isDiffMode = false
        guard id != activeTabID,
              let tab = tabs.first(where: { $0.id == id }) else { return }
        flushActiveTab()
        activate(tab: tab)
    }

    /// タブを閉じる。
    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        tabs.remove(at: idx)
        if wasActive {
            activate(tab: tabs.isEmpty ? nil : tabs[min(idx, tabs.count - 1)])
        }
    }

    /// アクティブタブの現在状態を保存する。
    func flushActiveTab() {
        guard let id = activeTabID,
              let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[idx].content = editorText
        tabs[idx].isDirty = isDirty
        tabs[idx].url = selectedFileURL
    }

    // MARK: - Private Helpers

    /// エディタ状態をタブに同期する。nil を渡すとエディタをクリアする。
    private func activate(tab: EditorTab?) {
        guard let tab else {
            activeTabID = nil
            editorText = ""
            selectedFileURL = nil
            isDirty = false
            savedText = ""
            outlineViewModel.update(text: "")
            return
        }
        activeTabID = tab.id
        editorText = tab.content
        selectedFileURL = tab.url
        isDirty = tab.isDirty
        savedText = tab.isDirty ? "" : tab.content
        outlineViewModel.update(text: tab.content)
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

    func markSaved() {
        savedText = editorText
        isDirty = false
        scheduleStatsUpdate()
        todoViewModel.update(text: editorText)
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

    // MARK: - AI Inline Completion

    private static let aiPlaceholder = "<!-- kobaamd-ai-generating -->"

    /// `{{プロンプト}}` を含む行をプレースホルダーに差し替えて AI を呼び出す。
    /// すべて @MainActor の editorText 操作で完結するため textView への直接アクセス不要。
    func startAIInlineCompletion(lineContent: String) {
        let trimmed = lineContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{{"), trimmed.hasSuffix("}}"), trimmed.count > 4 else { return }
        let prompt = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { return }

        // プロバイダー選択
        let provider: APIKeyStore.Provider
        if let k = APIKeyStore.load(for: .openai), !k.isEmpty      { provider = .openai }
        else if let k = APIKeyStore.load(for: .anthropic), !k.isEmpty { provider = .anthropic }
        else {
            // キー未設定: {{...}} 行の後ろにエラーを挿入
            editorText = editorText.replacingOccurrences(
                of: lineContent,
                with: lineContent + "\n> **AI エラー:** API キーが設定されていません（設定 ⌘, から登録）\n",
                range: editorText.range(of: lineContent)
            )
            markEdited()
            return
        }

        // コンテキスト（{{...}} 行より前の最大2000文字）
        let context: String
        if let range = editorText.range(of: lineContent) {
            context = String(editorText[..<range.lowerBound].suffix(2000))
        } else {
            context = ""
        }

        // {{...}} 行 → プレースホルダーへ差し替え
        let ph = Self.aiPlaceholder
        guard let lineRange = editorText.range(of: lineContent) else { return }
        editorText.replaceSubrange(lineRange, with: "\(ph)\n")
        isAIGenerating = true
        markEdited()

        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.aiTask = nil }
            do {
                // 30fps（33ms）バッファリング: トークンを溜めてまとめて editorText に反映する
                var buffer = ""
                var lastFlush = ContinuousClock.now
                let stream = self.aiService.stream(prompt: prompt, context: context, provider: provider)
                for try await token in stream {
                    if Task.isCancelled {
                        throw CancellationError()
                    }
                    buffer += token
                    let now = ContinuousClock.now
                    // 33ms 以上経過していたらバッファをフラッシュ
                    if now - lastFlush >= .milliseconds(33) {
                        if let r = self.editorText.range(of: ph) {
                            self.editorText.replaceSubrange(r.lowerBound..<r.lowerBound, with: buffer)
                        }
                        buffer = ""
                        lastFlush = now
                    }
                }
                // 残りバッファをフラッシュ
                if !buffer.isEmpty, let r = self.editorText.range(of: ph) {
                    self.editorText.replaceSubrange(r.lowerBound..<r.lowerBound, with: buffer)
                }
                // ストリーミング完了後にプレースホルダーを削除
                if let r = self.editorText.range(of: ph) {
                    self.editorText.removeSubrange(r)
                }
                self.isAIGenerating = false
                self.markEdited()
            } catch is CancellationError {
                // キャンセル時: プレースホルダーを削除し、それまでのテキストは残す
                if let r = self.editorText.range(of: ph) {
                    self.editorText.removeSubrange(r)
                }
                self.isAIGenerating = false
                self.markEdited()
            } catch {
                if let r = self.editorText.range(of: ph) {
                    self.editorText.replaceSubrange(r, with: "> **AI エラー:** \(error.localizedDescription)")
                    self.markEdited()
                }
                self.isAIGenerating = false
            }
        }
    }

    /// AI インライン補完をキャンセルする。生成済みテキストはエディタに残る。
    func cancelAIGeneration() {
        aiTask?.cancel()
        aiTask = nil
    }

    // MARK: - Confluence Sync

    func syncToConfluence() {
        confluenceSyncViewModel.performSync(
            fileURL: selectedFileURL,
            markdownContent: editorText,
            onError: { [weak self] error in self?.showAppError(error) }
        )
    }
}
