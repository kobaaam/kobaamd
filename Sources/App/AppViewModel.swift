import Foundation
import Observation

enum PreviewMode: String, CaseIterable {
    case split   = "Split"
    case wysiwyg = "WYSIWYG"
    case off     = "Off"
}

@Observable
final class AppViewModel {
    var selectedFileURL: URL? = nil
    var editorText: String = ""
    var isDirty: Bool = false
    var savedText: String = ""
    var previewScrollRatio: Double = 0
    var errorMessage: String? = nil
    var showError: Bool = false
    var previewMode: PreviewMode = .split
    var isSidebarVisible: Bool = true
    var isGitPanelVisible: Bool = false
    var isFileLoading: Bool = false

    let gitViewModel = GitViewModel()

    // MARK: - Tabs
    var tabs: [EditorTab] = []
    var activeTabID: UUID? = nil

    /// ファイルをタブで開く。既に開いていれば切り替えるだけ。
    func openInTab(url: URL, content: String) {
        if let existing = tabs.first(where: { $0.url == url }) {
            switchToTab(id: existing.id)
            return
        }
        flushActiveTab()
        let tab = EditorTab(url: url, content: content)
        tabs.append(tab)
        activeTabID = tab.id
        editorText = content
        selectedFileURL = url
        savedText = content
        isDirty = false
    }

    /// 新しい空タブを追加する。
    func newTab() {
        flushActiveTab()
        let tab = EditorTab()
        tabs.append(tab)
        activeTabID = tab.id
        editorText = ""
        selectedFileURL = nil
        isDirty = false
        savedText = ""
    }

    /// タブを切り替える。
    func switchToTab(id: UUID) {
        guard id != activeTabID else { return }
        flushActiveTab()
        activeTabID = id
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        editorText = tab.content
        selectedFileURL = tab.url
        isDirty = tab.isDirty
        savedText = tab.isDirty ? "" : tab.content
    }

    /// タブを閉じる。
    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTabID == id
        tabs.remove(at: idx)
        if wasActive {
            if tabs.isEmpty {
                activeTabID = nil
                editorText = ""
                selectedFileURL = nil
                isDirty = false
            } else {
                let t = tabs[min(idx, tabs.count - 1)]
                activeTabID = t.id
                editorText = t.content
                selectedFileURL = t.url
                isDirty = t.isDirty
                savedText = t.isDirty ? "" : t.content
            }
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

    // キャッシュ済みカウント — editorText 変更後に非同期で更新
    var lineCount: Int = 0
    var wordCount: Int = 0
    private var statsTask: Task<Void, Never>? = nil

    func markSaved() {
        savedText = editorText
        isDirty = false
        scheduleStatsUpdate()
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
    }

    func showAppError(_ error: AppError) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
