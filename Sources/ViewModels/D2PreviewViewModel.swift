import Foundation
import Observation

@Observable
@MainActor
final class D2PreviewViewModel {
    var svg: String = ""
    var errorMessage: String? = nil
    var isRendering: Bool = false
    var pendingCode: String = ""

    private var debounceTask: Task<Void, Never>? = nil

    func update(text: String) {
        debounceTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            svg = ""
            errorMessage = nil
            isRendering = false
            pendingCode = ""
            return
        }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.applyPendingCode(text)
        }
    }

    /// FSEvents 等の外部更新時は debounce を飛ばして即時反映する。
    func updateImmediate(text: String) {
        debounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            svg = ""
            errorMessage = nil
            isRendering = false
            pendingCode = ""
            return
        }
        applyPendingCode(text)
    }

    private func applyPendingCode(_ text: String) {
        isRendering = true
        errorMessage = nil
        pendingCode = text
    }
}
