import Foundation
import Observation

@Observable
@MainActor
final class PreviewViewModel {
    var html: String = ""
    private var debounceTask: Task<Void, Never>? = nil

    init() {}

    func update(text: String) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.html = MarkdownService().toHTML(text)
        }
    }
}
