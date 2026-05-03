import AppKit

@MainActor
protocol HighlightServiceProtocol: AnyObject {
    /// テキスト全体に対してハイライトを適用する（初回 / フルリビルド用）
    func highlight(_ textStorage: NSTextStorage)

    /// 編集範囲ベースの増分ハイライト。差分パースに失敗した場合はフルリビルドにフォールバックする実装でよい。
    func applyIncrementalHighlight(
        textStorage: NSTextStorage,
        editedRange: NSRange,
        changeInLength: Int
    )
}

extension HighlightServiceProtocol {
    /// デフォルト実装: 増分対応がないハイライタはフルリビルドにフォールバック。
    func applyIncrementalHighlight(
        textStorage: NSTextStorage,
        editedRange: NSRange,
        changeInLength: Int
    ) {
        highlight(textStorage)
    }
}
