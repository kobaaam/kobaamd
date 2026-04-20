import Foundation
import Observation

@Observable
@MainActor
final class PreviewViewModel {
    /// 初回ロード用フル HTML（シェル＋mermaid.js）
    var shellHTML: String = ""
    /// 差分更新用ボディコンテンツ
    var bodyHTML: String = ""
    var isRendering: Bool = false

    private var debounceTask: Task<Void, Never>? = nil
    private let service = MarkdownService()

    init() {}

    func update(text: String) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }

            await MainActor.run { self.isRendering = true }

            // Markdown レンダリングをバックグラウンドで実行してメインスレッドをブロックしない
            let (body, shell) = await Task.detached(priority: .userInitiated) { [service = self.service, shellEmpty = self.shellHTML.isEmpty] in
                let body = service.toBodyHTML(text)
                let shell = shellEmpty ? service.toHTML(text) : ""
                return (body, shell)
            }.value

            guard !Task.isCancelled else { return }
            self.bodyHTML = body
            if !shell.isEmpty { self.shellHTML = shell }
            self.isRendering = false
        }
    }
}
