import Foundation
import Observation

struct TodoItem: Identifiable, Equatable {
    let id: UUID
    let label: String
    let text: String
    let line: Int
}

@Observable
final class TodoViewModel {
    var items: [TodoItem] = []
    private var debounceTask: Task<Void, Never>? = nil

    // editorText の変更を 300ms デバウンスして TODO を再収集
    func update(text: String) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }

            let extracted = await Task.detached(priority: .userInitiated) {
                Self.parseTodos(from: text)
            }.value

            guard !Task.isCancelled else { return }
            self.items = extracted
        }
    }

    // テスト用（デバウンスなし）
    func extractTodos(from text: String) async -> [TodoItem] {
        await Task.detached(priority: .userInitiated) {
            Self.parseTodos(from: text)
        }.value
    }

    // 以下の記法を認識する（大文字小文字を区別しない）:
    //   TODO: テキスト
    //   FIXME: テキスト
    //   <!-- TODO: テキスト -->
    //   <!-- FIXME: テキスト -->
    private static func parseTodos(from text: String) -> [TodoItem] {
        let lines = text.components(separatedBy: .newlines)
        var results: [TodoItem] = []
        results.reserveCapacity(lines.count)

        let pattern = #"(?:<!--\s*)?(TODO|FIXME)\s*:\s*(.+?)(?:\s*-->)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        for (index, line) in lines.enumerated() {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            guard let match = regex.firstMatch(in: line, range: range) else { continue }

            let label = nsLine.substring(with: match.range(at: 1)).uppercased()
            let todoText = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)

            results.append(
                TodoItem(
                    id: UUID(),
                    label: label,
                    text: todoText,
                    line: index + 1
                )
            )
        }

        return results
    }
}
