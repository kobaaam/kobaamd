import Foundation
import Observation

@Observable
@MainActor
final class PreviewViewModel {
    /// 初回ロード用フル HTML（シェル＋mermaid.js）。
    /// 3MB 超の文字列なので Observation 対象から外し、更新通知は shellVersion で行う。
    @ObservationIgnored
    private(set) var shellHTML: String = ""
    var shellVersion: Int = 0
    /// 差分更新用ボディコンテンツ
    var bodyHTML: String = ""
    var isRendering: Bool = false

    private var debounceTask: Task<Void, Never>? = nil
    private let service = MarkdownService()
    private var lastTheme: ColorTheme?

    init() {}

    /// ファイル切替などで debounce を飛ばして即時に render させたい場合に使う。
    func updateImmediate(text: String, viewerMode: Bool = false) {
        update(text: text, viewerMode: viewerMode, immediate: true)
    }

    func update(text: String, viewerMode: Bool = false, immediate: Bool = false) {
        PerfLogger.event("PreviewViewModel.update", "len=\(text.count) viewer=\(viewerMode) immediate=\(immediate)")
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled, let self else { return }

            PerfLogger.begin("PreviewVM.render")
            await MainActor.run { self.isRendering = true }

            let currentTheme = AppState.shared.selectedTheme
            let themeChanged = self.lastTheme != currentTheme
            self.lastTheme = currentTheme

            // Markdown レンダリングをバックグラウンドで実行してメインスレッドをブロックしない
            let needsShell = self.shellHTML.isEmpty || themeChanged
            PerfLogger.begin("PreviewVM.markdown(needsShell=\(needsShell))")
            let (body, shell) = await Task.detached(priority: .userInitiated) { [service = self.service] in
                let body = service.toBodyHTML(text)
                // body を再利用して toHTML の二重 markdown パースを回避（perf）
                let shell = needsShell ? service.toHTML(text, body: body) : ""
                return (body, shell)
            }.value
            PerfLogger.event(
                "PreviewVM.markdown.awaitReturn",
                "bodyLen=\(body.count) shellLen=\(shell.count) needsShell=\(needsShell)"
            )
            PerfLogger.end("PreviewVM.markdown(needsShell=\(needsShell))")

            guard !Task.isCancelled else { return }
            let viewerStyle = """
            <style>
            body { max-width: 720px; margin: 0 auto; padding: 24px 48px; }
            </style>
            """
            PerfLogger.begin("PreviewVM.assign.bodyHTML")
            self.bodyHTML = viewerMode ? viewerStyle + body : body
            PerfLogger.end("PreviewVM.assign.bodyHTML")
            if !shell.isEmpty {
                PerfLogger.begin("PreviewVM.assign.shellHTML")
                self.shellHTML = shell
                self.shellVersion &+= 1
                PerfLogger.end("PreviewVM.assign.shellHTML")
            }
            self.isRendering = false
            PerfLogger.end("PreviewVM.render")
        }
    }
}
