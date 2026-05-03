import AppKit
import os
import SwiftTreeSitter
import TreeSitterMarkdown

@MainActor final class TreeSitterHighlightService: HighlightServiceProtocol {

    private let fallback = HighlightService()
    private let parser: Parser?
    private let language: Language?

    private var theme: ColorTheme { AppState.shared.selectedTheme }

    private let editorFont  = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let boldFont    = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
    private let h1Font      = NSFont.monospacedSystemFont(ofSize: 20, weight: .bold)
    private let h2Font      = NSFont.monospacedSystemFont(ofSize: 17, weight: .bold)
    private let h3Font      = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
    private let codeFont    = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    init() {
        let parser = Parser()

        do {
            let language = Language(language: tree_sitter_markdown())
            try parser.setLanguage(language)
            self.parser = parser
            self.language = language
        } catch {
            os_log(.error, "TreeSitter: parser init failed: %@", error.localizedDescription)
            self.parser = nil
            self.language = nil
        }
    }

    func highlight(_ textStorage: NSTextStorage) {
        guard let parser, language != nil else {
            fallback.highlight(textStorage)
            return
        }

        let source = textStorage.string

        guard !source.isEmpty else { return }

        guard let tree = parser.parse(source) else {
            os_log(.default, "TreeSitter: parse() returned nil, falling back to regex")
            fallback.highlight(textStorage)
            return
        }

        guard let rootNode = tree.rootNode, rootNode.range.length > 0 else {
            os_log(.default, "TreeSitter: rootNode empty, falling back to regex")
            fallback.highlight(textStorage)
            return
        }

        let currentTheme = theme
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        textStorage.setAttributes([
            .foregroundColor: currentTheme.editorText,
            .font: editorFont,
        ], range: fullRange)

        applyAttributes(
            to: rootNode,
            source: source,
            textStorage: textStorage,
            theme: currentTheme
        )
    }

    func applyIncrementalHighlight(
        textStorage: NSTextStorage,
        editedRange: NSRange,
        changeInLength: Int
    ) {
        // TODO: Use parser.parse(_:oldTree:) once edit propagation is wired in.
        highlight(textStorage)
    }

    private func applyAttributes(
        to node: Node,
        source: String,
        textStorage: NSTextStorage,
        theme: ColorTheme
    ) {
        let range = node.range

        if range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= textStorage.length {
            if let attributes = attributes(for: node, source: source, theme: theme) {
                // Merge onto existing attributes so child nodes override parents without additive buildup.
                var merged = textStorage.attributes(at: range.location, effectiveRange: nil)
                for (key, value) in attributes {
                    merged[key] = value
                }
                textStorage.setAttributes(merged, range: range)
            }
        }

        for index in 0..<node.childCount {
            guard let child = node.child(at: index) else { continue }
            applyAttributes(to: child, source: source, textStorage: textStorage, theme: theme)
        }
    }

    private func attributes(
        for node: Node,
        source: String,
        theme: ColorTheme
    ) -> [NSAttributedString.Key: Any]? {
        switch node.nodeType ?? "" {
        case "atx_heading":
            return headingAttributes(for: node, source: source, theme: theme)
        case "setext_heading":
            return headingAttributes(for: node, source: source, theme: theme)
        case "fenced_code_block", "indented_code_block":
            return [.foregroundColor: theme.codeColor, .font: codeFont]
        case "code_span":
            return [.foregroundColor: theme.codeColor, .font: codeFont]
        case "emphasis":
            return [.obliqueness: 0.2]
        case "strong_emphasis":
            return [.foregroundColor: theme.headingColor, .font: boldFont]
        case "link", "inline_link", "link_destination":
            return [.foregroundColor: theme.linkColor]
        case "block_quote":
            return [.foregroundColor: theme.mutedColor, .obliqueness: 0.1]
        case "list_marker_minus", "list_marker_plus", "list_marker_star", "list_marker_dot":
            return [.foregroundColor: theme.accentColor]
        case "thematic_break":
            return [.foregroundColor: theme.mutedColor]
        default:
            return nil
        }
    }

    private func headingAttributes(
        for node: Node,
        source: String,
        theme: ColorTheme
    ) -> [NSAttributedString.Key: Any] {
        let markerCount = headingMarkerCount(for: node, source: source)

        switch markerCount {
        case 1:
            return [.foregroundColor: theme.headingColor, .font: h1Font]
        case 2:
            return [.foregroundColor: theme.headingColor, .font: h2Font]
        default:
            return [.foregroundColor: theme.headingColor, .font: h3Font]
        }
    }

    private func headingMarkerCount(for node: Node, source: String) -> Int {
        guard let stringRange = Range(node.range, in: source) else { return 3 }

        let headingText = String(source[stringRange])
        let firstLine = headingText.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""

        if firstLine.hasPrefix("#") {
            let markerCount = firstLine.prefix { $0 == "#" }.count
            return max(1, min(markerCount, 6))
        }

        if headingText.contains("\n=") {
            return 1
        }

        if headingText.contains("\n-") {
            return 2
        }

        return 3
    }
}
