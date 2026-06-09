import Testing
@testable import kobaamd
import Foundation

@Suite("BacklinksScanner")
struct BacklinksScannerTests {
    private let targetURL = URL(fileURLWithPath: "/tmp/note.md")
    private let sourceURL = URL(fileURLWithPath: "/tmp/source.md")

    @Test("Detects wikilink as linked")
    func detectsWikiLink() {
        let result = BacklinksScanner.scan(
            sourceURL: sourceURL,
            sourceContent: "Reference [[note]] here.",
            targetURL: targetURL
        )

        #expect(result.linked.count == 1)
        #expect(result.linked.first?.kind == .linked)
        #expect(result.linked.first?.matchedText == "[[note]]")
        #expect(result.unlinked.isEmpty)
    }

    @Test("Detects wikilink alias as linked")
    func detectsWikiLinkAlias() {
        let result = BacklinksScanner.scan(
            sourceURL: sourceURL,
            sourceContent: "Reference [[note|alias]] here.",
            targetURL: targetURL
        )

        #expect(result.linked.count == 1)
        #expect(result.linked.first?.matchedText == "[[note|alias]]")
    }

    @Test("Detects wikilink heading as linked")
    func detectsWikiLinkHeading() {
        let result = BacklinksScanner.scan(
            sourceURL: sourceURL,
            sourceContent: "Reference [[note#heading]] here.",
            targetURL: targetURL
        )

        #expect(result.linked.count == 1)
        #expect(result.linked.first?.matchedText == "[[note#heading]]")
    }

    @Test("Detects markdown links as linked")
    func detectsMarkdownLinks() {
        let content = """
        [a]( note.md )
        [b](./folder/note.md)
        [c](note)
        """
        let result = BacklinksScanner.scan(
            sourceURL: sourceURL,
            sourceContent: content,
            targetURL: targetURL
        )

        #expect(result.linked.count == 3)
        #expect(result.unlinked.isEmpty)
    }

    @Test("Detects plain word as unlinked candidate")
    func detectsPlainWordAsUnlinked() {
        let result = BacklinksScanner.scan(
            sourceURL: sourceURL,
            sourceContent: "This note is great.",
            targetURL: targetURL
        )

        #expect(result.linked.isEmpty)
        #expect(result.unlinked.count == 1)
        #expect(result.unlinked.first?.matchedText.lowercased() == "note")
    }

    @Test("Does not double count linked occurrence as unlinked")
    func doesNotDoubleCountLinkedOccurrence() {
        let result = BacklinksScanner.scan(
            sourceURL: sourceURL,
            sourceContent: "This [[note]] is linked.",
            targetURL: targetURL
        )

        #expect(result.linked.count == 1)
        #expect(result.unlinked.isEmpty)
    }

    @Test("Skips short basename for unlinked detection")
    func skipsShortBasename() {
        let shortTarget = URL(fileURLWithPath: "/tmp/ab.md")
        let result = BacklinksScanner.scan(
            sourceURL: sourceURL,
            sourceContent: "ab is mentioned here.",
            targetURL: shortTarget
        )

        #expect(result.linked.isEmpty)
        #expect(result.unlinked.isEmpty)
    }

    @Test("Skips self reference")
    func skipsSelfReference() {
        let result = BacklinksScanner.scan(
            sourceURL: targetURL,
            sourceContent: "Reference [[note]] here.",
            targetURL: targetURL
        )

        #expect(result.linked.isEmpty)
        #expect(result.unlinked.isEmpty)
    }

    @Test("Snippet builder truncates with ellipses")
    func snippetBuilderTruncatesWithEllipses() throws {
        let content = String(repeating: "a", count: 40) + " note " + String(repeating: "b", count: 40)
        let result = BacklinksScanner.scan(
            sourceURL: sourceURL,
            sourceContent: content,
            targetURL: targetURL
        )

        let snippet = try #require(result.unlinked.first?.snippet)
        #expect(snippet.hasPrefix("..."))
        #expect(snippet.contains("note"))
        #expect(snippet.hasSuffix("..."))
    }

    @Test("Line number is 1 based")
    func lineNumberIsOneBased() {
        let content = """
        first
        second
        note here
        """
        let result = BacklinksScanner.scan(
            sourceURL: sourceURL,
            sourceContent: content,
            targetURL: targetURL
        )

        #expect(result.unlinked.first?.line == 3)
    }

    @Test("Convert to link replaces only matched range")
    func convertToLinkReplacesMatchedRange() throws {
        let content = "This note is here and notebook stays."
        let scan = BacklinksScanner.scan(
            sourceURL: sourceURL,
            sourceContent: content,
            targetURL: targetURL
        )
        let backlink = try #require(scan.unlinked.first)

        let converted = BacklinksScanner.convertToLink(
            sourceContent: content,
            range: backlink.matchRange,
            targetURL: targetURL
        )

        #expect(converted == "This [[note]] is here and notebook stays.")
    }
}
