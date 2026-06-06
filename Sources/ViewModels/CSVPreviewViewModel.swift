import Foundation
import Observation

/// CSV プレビュー用の ViewModel。
/// D2PreviewViewModel と同じ debounce パターンを踏襲する。
@Observable
@MainActor
final class CSVPreviewViewModel {
    /// パース済みテーブルデータ
    var table: CSVTable = CSVTable(headers: [], rows: [], isTruncated: false, columnCount: 0)

    private var debounceTask: Task<Void, Never>? = nil

    /// テキスト変更を受け取り、300ms debounce 後に CSV をパースしてテーブルを更新する。
    func update(text: String) {
        debounceTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            table = CSVTable(headers: [], rows: [], isTruncated: false, columnCount: 0)
            return
        }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.applyParse(text)
        }
    }

    /// ファイル切替時など、debounce なしで即座にパースする。
    func updateImmediate(text: String) {
        debounceTask?.cancel()
        applyParse(text)
    }

    private func applyParse(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            table = CSVTable(headers: [], rows: [], isTruncated: false, columnCount: 0)
            return
        }
        table = CSVParser.parse(text)
    }
}
