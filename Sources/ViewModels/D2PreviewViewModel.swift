import Foundation
import Observation

@Observable
@MainActor
final class D2PreviewViewModel {
    var svg: String = ""
    var errorMessage: String? = nil
    var isRendering: Bool = false

    private var debounceTask: Task<Void, Never>? = nil
    private let service = D2Service()

    func update(text: String) {
        debounceTask?.cancel()

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            svg = ""
            errorMessage = nil
            isRendering = false
            return
        }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }

            self.isRendering = true
            self.errorMessage = nil

            do {
                let renderedSVG = try await service.renderSVG(code: text)
                guard !Task.isCancelled else { return }
                self.svg = renderedSVG
                self.errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.svg = ""
                self.errorMessage = error.localizedDescription
            }

            self.isRendering = false
        }
    }
}
