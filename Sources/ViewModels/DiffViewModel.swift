import Foundation
import Observation

@Observable
@MainActor
final class DiffViewModel {
    var textA: String = ""
    var textB: String = ""
    var fileNameA: String = ""
    var fileNameB: String = ""
    var lines: [DiffLine] = []

    // MARK: - Rendered diff mode

    var isRenderedMode: Bool = false
    var renderedHTMLForA: String = ""
    var renderedHTMLForB: String = ""

    private var debounceTask: Task<Void, Never>?

    struct DiffLine: Identifiable, Sendable {
        let id = UUID()
        let text: String
        let kind: Kind

        enum Kind: Equatable, Sendable {
            case added
            case removed
            case context
            case header
        }
    }

    func scheduleUpdate() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.lines = await Self.computeDiff(a: self.textA, b: self.textB)
            if self.isRenderedMode {
                self.updateRenderedHTML()
            }
        }
    }

    func toggleRenderedMode() {
        isRenderedMode.toggle()
        if isRenderedMode {
            updateRenderedHTML()
        }
    }

    func updateRenderedHTML() {
        let themeCSS = AppState.shared.selectedTheme.previewCSS
        let textA = self.textA
        let textB = self.textB
        let lines = self.lines
        let fileNameA = self.fileNameA
        let fileNameB = self.fileNameB

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let bodyA = MarkdownService().toBodyHTML(textA)
                let bodyB = MarkdownService().toBodyHTML(textB)

                let addedCount = lines.filter { $0.kind == .added }.count
                let removedCount = lines.filter { $0.kind == .removed }.count

                let labelA = fileNameA.isEmpty ? "A (Old)" : fileNameA
                let labelB = fileNameB.isEmpty ? "B (New)" : fileNameB

                let statsA = removedCount > 0
                    ? "<div class=\"diff-stats\">\(removedCount) line\(removedCount == 1 ? "" : "s") removed</div>"
                    : ""
                let statsB = addedCount > 0
                    ? "<div class=\"diff-stats\">\(addedCount) line\(addedCount == 1 ? "" : "s") added</div>"
                    : ""

                // 削除行ハイライト（サイドA用）
                let removedLines = lines.filter { $0.kind == .removed }
                let removedHighlightHTML: String
                if removedLines.isEmpty {
                    removedHighlightHTML = ""
                } else {
                    let rows = removedLines.map { line in
                        "<div class=\"diff-line-removed\">\(DiffViewModel.escapeHTML(String(line.text.dropFirst())))</div>"
                    }.joined(separator: "\n")
                    removedHighlightHTML = """
                    <div class="diff-highlight-section">
                    <h4>Removed Lines</h4>
                    \(rows)
                    </div>
                    """
                }

                // 追加行ハイライト（サイドB用）
                let addedLines = lines.filter { $0.kind == .added }
                let addedHighlightHTML: String
                if addedLines.isEmpty {
                    addedHighlightHTML = ""
                } else {
                    let rows = addedLines.map { line in
                        "<div class=\"diff-line-added\">\(DiffViewModel.escapeHTML(String(line.text.dropFirst())))</div>"
                    }.joined(separator: "\n")
                    addedHighlightHTML = """
                    <div class="diff-highlight-section">
                    <h4>Added Lines</h4>
                    \(rows)
                    </div>
                    """
                }

                let htmlA = DiffViewModel.buildRenderedHTML(
                    bodyHTML: bodyA,
                    bannerClass: "diff-banner-old",
                    sideLabel: "Old",
                    fileName: labelA,
                    statsHTML: statsA,
                    diffHighlightHTML: removedHighlightHTML,
                    themeCSS: themeCSS
                )
                let htmlB = DiffViewModel.buildRenderedHTML(
                    bodyHTML: bodyB,
                    bannerClass: "diff-banner-new",
                    sideLabel: "New",
                    fileName: labelB,
                    statsHTML: statsB,
                    diffHighlightHTML: addedHighlightHTML,
                    themeCSS: themeCSS
                )
                return (htmlA, htmlB)
            }.value

            self.renderedHTMLForA = result.0
            self.renderedHTMLForB = result.1
        }
    }

    nonisolated private static func buildRenderedHTML(
        bodyHTML: String,
        bannerClass: String,
        sideLabel: String,
        fileName: String,
        statsHTML: String,
        diffHighlightHTML: String,
        themeCSS: String
    ) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <style>
            \(themeCSS)
            </style>
            <style>
            body { margin: 0; padding: 16px; }
            .diff-banner {
                padding: 8px 16px;
                font-size: 13px;
                font-weight: 600;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                border-radius: 6px;
                margin-bottom: 16px;
            }
            .diff-banner-old {
                background: rgba(255,59,48,0.12);
                color: #ff3b30;
            }
            .diff-banner-new {
                background: rgba(52,199,89,0.12);
                color: #34c759;
            }
            .diff-stats {
                font-size: 12px;
                color: #8e8e93;
                margin-top: 4px;
            }
            .diff-highlight-section {
                margin-top: 16px;
                border-top: 1px solid rgba(0,0,0,0.1);
                padding-top: 12px;
            }
            .diff-highlight-section h4 {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 11px;
                font-weight: 600;
                color: #8e8e93;
                text-transform: uppercase;
                letter-spacing: 0.5px;
                margin: 0 0 8px;
            }
            .diff-line-added {
                background: rgba(52,199,89,0.18);
                border-left: 3px solid #34c759;
                padding: 2px 8px;
                margin: 2px 0;
                font-family: ui-monospace, monospace;
                font-size: 12px;
                white-space: pre-wrap;
                border-radius: 2px;
            }
            .diff-line-removed {
                background: rgba(255,59,48,0.15);
                border-left: 3px solid #ff3b30;
                padding: 2px 8px;
                margin: 2px 0;
                font-family: ui-monospace, monospace;
                font-size: 12px;
                white-space: pre-wrap;
                border-radius: 2px;
            }
            @media (prefers-color-scheme: dark) {
                body { background: #1e1e1e; color: #d4d4d4; }
                .diff-banner-old {
                    background: rgba(255,59,48,0.20);
                    color: #ff6961;
                }
                .diff-banner-new {
                    background: rgba(52,199,89,0.20);
                    color: #4cd964;
                }
                .diff-stats { color: #a0a0a8; }
                .diff-line-added {
                    background: rgba(52,199,89,0.25);
                }
                .diff-line-removed {
                    background: rgba(255,59,48,0.22);
                }
                .diff-highlight-section {
                    border-top-color: rgba(255,255,255,0.1);
                }
            }
            </style>
        </head>
        <body>
        <div class="diff-banner \(bannerClass)">\(sideLabel): \(Self.escapeHTML(fileName))\(statsHTML)</div>
        \(bodyHTML)
        \(diffHighlightHTML)
        </body>
        </html>
        """
    }

    // MARK: - テスト用内部公開（escapeHTML のラッパー）
    nonisolated static func testableEscapeHTML(_ string: String) -> String {
        escapeHTML(string)
    }

    static func testableComputeDiff(a: String, b: String) async -> [DiffLine] {
        await computeDiff(a: a, b: b)
    }

    nonisolated private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    nonisolated private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func computeDiff(a: String, b: String) async -> [DiffLine] {
        guard a != b else { return [] }

        return await Task.detached(priority: .userInitiated) {
            let oldLines = splitLines(a)
            let newLines = splitLines(b)

            guard oldLines != newLines else { return [] }

            let diff = newLines.difference(from: oldLines)
            guard !diff.isEmpty else { return [] }

            var removalsByOffset: [Int: String] = [:]
            var insertionsByOffset: [Int: String] = [:]

            for change in diff {
                switch change {
                case let .remove(offset, element, _):
                    removalsByOffset[offset] = element
                case let .insert(offset, element, _):
                    insertionsByOffset[offset] = element
                }
            }

            var lines: [DiffLine] = []
            var oldIndex = 0
            var newIndex = 0

            while oldIndex < oldLines.count || newIndex < newLines.count {
                if let removed = removalsByOffset[oldIndex] {
                    lines.append(DiffLine(text: "-\(removed)", kind: .removed))
                    oldIndex += 1
                    continue
                }

                if let added = insertionsByOffset[newIndex] {
                    lines.append(DiffLine(text: "+\(added)", kind: .added))
                    newIndex += 1
                    continue
                }

                if oldIndex < oldLines.count && newIndex < newLines.count {
                    lines.append(DiffLine(text: newLines[newIndex], kind: .context))
                    oldIndex += 1
                    newIndex += 1
                    continue
                }

                if oldIndex < oldLines.count {
                    lines.append(DiffLine(text: "-\(oldLines[oldIndex])", kind: .removed))
                    oldIndex += 1
                    continue
                }

                lines.append(DiffLine(text: "+\(newLines[newIndex])", kind: .added))
                newIndex += 1
            }

            return lines
        }.value
    }
}
