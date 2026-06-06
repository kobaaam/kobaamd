import Foundation

// MARK: - E1 viewer layout (KMD-237, Re-concept refresh)

enum E1FileKind: Equatable {
    case none
    case markdown
    case d2
    case csv
    case other
}

/// Markdown ビューアの表示モード（Gemini レイアウト提案）
enum E1MarkdownViewMode: String, CaseIterable, Identifiable {
    case split = "分割"
    case editor = "エディタ"
    case preview = "プレビュー"

    var id: String { rawValue }
}

enum E1ViewerTab: String, CaseIterable, Identifiable {
    case rendered = "Rendered"
    case source = "Source"
    case d2 = "D2"
    case diff = "Diff"
    case csv = "CSV"

    var id: String { rawValue }

    var isMarkdownPane: Bool {
        self == .rendered || self == .source
    }
}

enum E1ViewerLayoutPolicy {
    static let defaultLeftWidth: CGFloat = 240
    static let defaultRightFraction: CGFloat = 0.6
    static let defaultMdSplitFraction: CGFloat = 0.5

    static func fileKind(for url: URL?) -> E1FileKind {
        guard let url else { return .none }
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" || ext.isEmpty { return .markdown }
        if ext == "d2" { return .d2 }
        if ext == "csv" { return .csv }
        return .other
    }

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

    static func defaultMarkdownMode(for kind: E1FileKind) -> E1MarkdownViewMode {
        kind == .markdown ? .split : .editor
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

    static func usesMarkdownSplit(kind: E1FileKind, mode: E1MarkdownViewMode) -> Bool {
        kind == .markdown && mode == .split
    }
}