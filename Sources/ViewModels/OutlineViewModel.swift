import Foundation
import Observation

struct OutlineItem: Identifiable, Equatable {
    let id = UUID()
    let level: Int
    let text: String
    let line: Int
}

@Observable
final class OutlineViewModel {
    var items: [OutlineItem] = []
    var totalLines: Int = 0

    private var debounceTask: Task<Void, Never>? = nil

    /// editorText の変更を 300ms デバウンスしてアウトライン更新する。
    /// `AppViewModel` が nonisolated のため、このメソッドも nonisolated で呼べるように実装する。
    func update(text: String) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }

            let extracted = await Task.detached(priority: .userInitiated) {
                Self.parseHeadings(from: text)
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.items = extracted
                self?.totalLines = text.components(separatedBy: "\n").count
            }
        }
    }

    /// テストから直接呼べるよう公開する（デバウンスなし）
    func extractHeadings(from text: String) async -> [OutlineItem] {
        await Task.detached(priority: .userInitiated) {
            Self.parseHeadings(from: text)
        }.value
    }

    private static func parseHeadings(from text: String) -> [OutlineItem] {
        let lines = text.components(separatedBy: .newlines)
        var extracted: [OutlineItem] = []
        extracted.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            guard line.first == "#" else { continue }

            let level = line.prefix { $0 == "#" }.count
            guard (1...6).contains(level) else { continue }

            let markerEnd = line.index(line.startIndex, offsetBy: level)
            guard markerEnd < line.endIndex, line[markerEnd] == " " else { continue }

            let textStart = line.index(after: markerEnd)
            let headingText = String(line[textStart...]).trimmingCharacters(in: .whitespaces)

            extracted.append(
                OutlineItem(
                    level: level,
                    text: headingText,
                    line: index + 1
                )
            )
        }

        return extracted
    }
}
