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
    private var lastTheme: ColorTheme?

    init() {}

    func update(text: String) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }

            await MainActor.run { self.isRendering = true }

            let currentTheme = AppState.shared.selectedTheme
            let themeChanged = self.lastTheme != currentTheme
            self.lastTheme = currentTheme

            // Markdown レンダリングをバックグラウンドで実行してメインスレッドをブロックしない
            let needsShell = self.shellHTML.isEmpty || themeChanged
            let (body, shell) = await Task.detached(priority: .userInitiated) { [service = self.service] in
                let body = service.toBodyHTML(text)
                let shell = needsShell ? service.toHTML(text) : ""
                return (body, shell)
            }.value

            guard !Task.isCancelled else { return }
            self.bodyHTML = body
            if !shell.isEmpty { self.shellHTML = shell }
            self.isRendering = false
        }
    }
}
