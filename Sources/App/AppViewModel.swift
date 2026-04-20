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

    let gitViewModel = GitViewModel()

    var lineCount: Int {
        guard !editorText.isEmpty else { return 0 }
        return editorText.components(separatedBy: "\n").count
    }

    var wordCount: Int {
        guard !editorText.isEmpty else { return 0 }
        return editorText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    func markSaved() {
        savedText = editorText
        isDirty = false
    }

    func markEdited() {
        isDirty = editorText != savedText
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
