import Foundation
import Observation

@Observable
final class AppViewModel {
    var selectedFileURL: URL? = nil
    var editorText: String = ""
    var isDirty: Bool = false
    var savedText: String = ""
    var errorMessage: String? = nil
    var showError: Bool = false

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
