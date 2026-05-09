import Foundation
import Observation

@Observable
@MainActor
final class FrontmatterViewModel {
    var frontmatter = Frontmatter()
    var hasFrontmatter: Bool = false
    var isExpanded: Bool = false
    private(set) var bodyText: String = ""
    private var leadingBlankLine: Bool = false
    private var lastSyncedText: String? = nil

    func update(from text: String) {
        if lastSyncedText == text {
            return
        }

        let split = Frontmatter.split(text: text)
        let parsed = split.frontmatterText.map(Frontmatter.parse) ?? Frontmatter()

        if hasFrontmatter == (split.frontmatterText != nil),
           bodyText == split.body,
           leadingBlankLine == split.leadingBlankLine,
           frontmatter == parsed {
            lastSyncedText = text
            return
        }

        hasFrontmatter = split.frontmatterText != nil
        bodyText = split.body
        leadingBlankLine = split.leadingBlankLine
        frontmatter = parsed
        lastSyncedText = text
    }

    func apply(to text: inout String) {
        let rendered = frontmatter.render()
        let rebuilt = rendered + bodyText

        if text != rebuilt {
            text = rebuilt
        }

        hasFrontmatter = !rendered.isEmpty
        leadingBlankLine = bodyText.hasPrefix("\n")
        lastSyncedText = rebuilt
    }

    func insertTemplate(into text: inout String) {
        let rebuilt = Frontmatter.template() + text
        text = rebuilt
        update(from: rebuilt)
    }
}
