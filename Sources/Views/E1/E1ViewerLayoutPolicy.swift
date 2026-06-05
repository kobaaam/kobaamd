import Foundation

// MARK: - E1 viewer layout (KMD-237)

enum E1FileKind: Equatable {
    case none
    case markdown
    case d2
    case csv
    case other
}

enum E1ViewerLayoutPolicy {
    static func fileKind(for url: URL?) -> E1FileKind {
        guard let url else { return .none }
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" || ext.isEmpty { return .markdown }
        if ext == "d2" { return .d2 }
        if ext == "csv" { return .csv }
        return .other
    }

    /// 拡張子に応じた初期 Viewer タブ。
    static func defaultTab(for kind: E1FileKind) -> E1ViewerTab {
        switch kind {
        case .none: return .source
        case .markdown: return .rendered
        case .d2: return .d2
        case .csv: return .csv
        case .other: return .source
        }
    }

    static func defaultTab(for url: URL?) -> E1ViewerTab {
        defaultTab(for: fileKind(for: url))
    }

    static func isTabEnabled(_ tab: E1ViewerTab, kind: E1FileKind) -> Bool {
        switch kind {
        case .none:
            return tab == .source
        case .markdown:
            switch tab {
            case .rendered, .source, .diff: return true
            case .d2, .csv: return false
            }
        case .d2:
            return tab == .d2 || tab == .diff || tab == .source
        case .csv:
            return tab == .csv || tab == .diff || tab == .source
        case .other:
            return tab == .source || tab == .diff
        }
    }

    /// Markdown で Rendered+Source の Split を使うか（KMD-235/236）。
    static func usesMarkdownSplit(kind: E1FileKind, splitEnabled: Bool, selectedTab: E1ViewerTab) -> Bool {
        kind == .markdown && splitEnabled && selectedTab.isMarkdownPane
    }
}