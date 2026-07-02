import AppKit
import Testing
@testable import kobaamd

/// シンプルな性能スモークテスト
/// - 1000行 / 5000行 Markdown で highlight() を 1 回呼んだ際の時間が一定閾値内に収まることを確認
/// - 閾値は環境依存なので assert はせず、デバッグ出力のみ（CI で regression を検知する基盤）
@MainActor
@Suite("HighlightBenchmarks")
struct HighlightBenchmarks {

    private func generateMarkdown(lines: Int) -> String {
        var lines_array: [String] = []
        for i in 0..<lines {
            switch i % 10 {
            case 0: lines_array.append("# Heading \(i)")
            case 1: lines_array.append("## Sub heading \(i)")
            case 2: lines_array.append("```swift\nlet x = \(i)\n```")
            case 3: lines_array.append("**bold text** and *italic* and `code`")
            case 4: lines_array.append("[link](https://example.com)")
            case 5: lines_array.append("> blockquote line \(i)")
            case 6: lines_array.append("- list item \(i)")
            default: lines_array.append("Regular paragraph text at line \(i). Lorem ipsum dolor sit amet.")
            }
        }
        return lines_array.joined(separator: "\n")
    }

    @Test("TreeSitter highlight() — 1000行 smoke benchmark")
    func benchmark1000Lines() {
        let markdown = generateMarkdown(lines: 1000)
        let storage = NSTextStorage(string: markdown)
        let service = TreeSitterHighlightService()

        let start = Date()
        service.highlight(storage)
        let elapsed = Date().timeIntervalSince(start) * 1000

        // smoke: 10秒以内に完了すること（パフォーマンス regression の大まかな検知用）
        print("[HighlightBenchmark] 1000行: \(String(format: "%.1f", elapsed))ms")
        #expect(elapsed < 10_000, "1000行ハイライトが10秒以内に完了しなかった: \(elapsed)ms")
    }

    @Test("TreeSitter highlight() — 5000行 smoke benchmark")
    func benchmark5000Lines() {
        let markdown = generateMarkdown(lines: 5000)
        let storage = NSTextStorage(string: markdown)
        let service = TreeSitterHighlightService()

        let start = Date()
        service.highlight(storage)
        let elapsed = Date().timeIntervalSince(start) * 1000

        print("[HighlightBenchmark] 5000行: \(String(format: "%.1f", elapsed))ms")
        #expect(elapsed < 30_000, "5000行ハイライトが30秒以内に完了しなかった: \(elapsed)ms")
    }

    @Test("HighlightService(正規表現版) — 1000行 比較 benchmark")
    func benchmarkRegex1000Lines() {
        let markdown = generateMarkdown(lines: 1000)
        let storage = NSTextStorage(string: markdown)
        let service = HighlightService()

        let start = Date()
        service.highlight(storage)
        let elapsed = Date().timeIntervalSince(start) * 1000

        print("[HighlightBenchmark] 正規表現1000行: \(String(format: "%.1f", elapsed))ms")
        #expect(elapsed < 10_000)
    }
}
