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
    private let markdownService = MarkdownService()

    struct DiffLine: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind

        enum Kind {
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

    private func updateRenderedHTML() {
        let bodyA = markdownService.toBodyHTML(textA)
        let bodyB = markdownService.toBodyHTML(textB)

        let addedCount = lines.filter { $0.kind == .added }.count
        let removedCount = lines.filter { $0.kind == .removed }.count

        let labelA = fileNameA.isEmpty ? "A (Old)" : fileNameA
        let labelB = fileNameB.isEmpty ? "B (New)" : fileNameB

        let statsA = removedCount > 0 ? "<div class=\"diff-stats\">\(removedCount) line\(removedCount == 1 ? "" : "s") removed</div>" : ""
        let statsB = addedCount > 0 ? "<div class=\"diff-stats\">\(addedCount) line\(addedCount == 1 ? "" : "s") added</div>" : ""

        renderedHTMLForA = Self.buildRenderedHTML(
            bodyHTML: bodyA,
            bannerClass: "diff-banner-old",
            sideLabel: "Old",
            fileName: labelA,
            statsHTML: statsA
        )
        renderedHTMLForB = Self.buildRenderedHTML(
            bodyHTML: bodyB,
            bannerClass: "diff-banner-new",
            sideLabel: "New",
            fileName: labelB,
            statsHTML: statsB
        )
    }

    private static func buildRenderedHTML(
        bodyHTML: String,
        bannerClass: String,
        sideLabel: String,
        fileName: String,
        statsHTML: String
    ) -> String {
        let themeCSS = AppState.shared.selectedTheme.previewCSS
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
            </style>
        </head>
        <body>
        <div class="diff-banner \(bannerClass)">\(sideLabel): \(Self.escapeHTML(fileName))\(statsHTML)</div>
        \(bodyHTML)
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func computeDiff(a: String, b: String) async -> [DiffLine] {
        let tmpA = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kobaamd_diff_a.txt")
        let tmpB = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kobaamd_diff_b.txt")
        try? a.write(to: tmpA, atomically: true, encoding: .utf8)
        try? b.write(to: tmpB, atomically: true, encoding: .utf8)

        return await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["diff", "--no-index", "--color=never", tmpA.path, tmpB.path]

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()

            try? proc.run()
            proc.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if output.isEmpty { return [] }

            return output.components(separatedBy: "\n").compactMap { raw in
                guard !raw.isEmpty else { return nil }

                if raw.hasPrefix("+++") || raw.hasPrefix("---") || raw.hasPrefix("diff") || raw.hasPrefix("index") {
                    return DiffViewModel.DiffLine(text: raw, kind: .header)
                } else if raw.hasPrefix("+") {
                    return DiffViewModel.DiffLine(text: raw, kind: .added)
                } else if raw.hasPrefix("-") {
                    return DiffViewModel.DiffLine(text: raw, kind: .removed)
                } else if raw.hasPrefix("@@") {
                    return DiffViewModel.DiffLine(text: raw, kind: .header)
                } else {
                    return DiffViewModel.DiffLine(text: raw, kind: .context)
                }
            }
        }.value
    }
}
