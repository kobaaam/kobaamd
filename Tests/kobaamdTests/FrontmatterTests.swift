import Testing
@testable import kobaamd

@Suite("Frontmatter")
struct FrontmatterTests {
    @Test("parse_blockListTags")
    func parseBlockListTags() {
        let parsed = Frontmatter.parse(yaml: """
        tags:
          - swift
          - ios
        """)

        #expect(parsed.tags == ["swift", "ios"])
    }

    @Test("parse_inlineArrayTags")
    func parseInlineArrayTags() {
        let parsed = Frontmatter.parse(yaml: "tags: [swift, ios]")

        #expect(parsed.tags == ["swift", "ios"])
    }

    @Test("parse_singleTag")
    func parseSingleTag() {
        let parsed = Frontmatter.parse(yaml: "tags: swift")

        #expect(parsed.tags == ["swift"])
    }

    @Test("parse_titleAndCategory")
    func parseTitleAndCategory() {
        let parsed = Frontmatter.parse(yaml: """
        title: Hello
        category: Notes
        """)

        #expect(parsed.title == "Hello")
        #expect(parsed.category == "Notes")
    }

    @Test("parse_quotedString")
    func parseQuotedString() {
        let parsed = Frontmatter.parse(yaml: #"title: "Hello World""#)

        #expect(parsed.title == "Hello World")
    }

    @Test("parse_extraLinesPreserved")
    func parseExtraLinesPreserved() {
        let parsed = Frontmatter.parse(yaml: """
        priority: high
        # keep me
        """)

        #expect(parsed.extraLines == ["priority: high", "# keep me"])
    }

    @Test("parse_nestedTriggersWarning")
    func parseNestedTriggersWarning() {
        let parsed = Frontmatter.parse(yaml: """
        meta:
          level: 1
        """)

        #expect(parsed.parseError != nil)
        #expect(parsed.extraLines == ["meta:", "  level: 1"])
    }

    @Test("render_emptyReturnsEmpty")
    func renderEmptyReturnsEmpty() {
        #expect(Frontmatter().render().isEmpty)
    }

    @Test("render_roundTrip")
    func renderRoundTrip() {
        let source = Frontmatter.parse(yaml: """
        title: Hello
        category: Notes
        tags:
          - swift
          - ios
        aliases: [kb, notes]
        date: 2026-05-09T12:00:00Z
        description: "Hello World"
        priority: high
        """)

        let reparsed = Frontmatter.parse(yaml: Frontmatter.split(text: source.render()).frontmatterText ?? "")

        #expect(reparsed.title == "Hello")
        #expect(reparsed.category == "Notes")
        #expect(reparsed.tags == ["swift", "ios"])
        #expect(reparsed.aliases == ["kb", "notes"])
        #expect(reparsed.date == "2026-05-09T12:00:00Z")
        #expect(reparsed.description == "Hello World")
        #expect(reparsed.extraLines == ["priority: high"])
    }

    @Test("render_blockListFormatForTags")
    func renderBlockListFormatForTags() {
        let rendered = Frontmatter(tags: ["swift", "ios"]).render()
        let reparsed = Frontmatter.parse(yaml: Frontmatter.split(text: rendered).frontmatterText ?? "")

        #expect(reparsed.tags == ["swift", "ios"])
        #expect(rendered.contains("tags:\n  - swift\n  - ios"))
    }

    @Test("split_noFrontmatter")
    func splitNoFrontmatter() {
        let result = Frontmatter.split(text: "body text")

        #expect(result.frontmatterText == nil)
        #expect(result.body == "body text")
    }

    @Test("split_withFrontmatter")
    func splitWithFrontmatter() {
        let result = Frontmatter.split(text: """
        ---
        title: Hello
        ---
        body
        """)

        #expect(result.frontmatterText == "title: Hello")
        #expect(result.body == "body")
    }

    @MainActor
    @Test("vm_insertTemplate")
    func vmInsertTemplate() {
        let vm = FrontmatterViewModel()
        var text = ""

        vm.insertTemplate(into: &text)
        vm.update(from: text)

        #expect(vm.hasFrontmatter)
        #expect(text.hasPrefix("---\ntitle:\ntags:\n---\n"))
    }

    @MainActor
    @Test("vm_apply_preservesBody")
    func vmApplyPreservesBody() {
        let vm = FrontmatterViewModel()
        var text = """
        ---
        title: Old
        ---
        body
        text
        """

        vm.update(from: text)
        vm.frontmatter.title = "New"
        vm.apply(to: &text)

        #expect(text.contains("title: New"))
        #expect(text.hasSuffix("body\ntext"))
    }

    @MainActor
    @Test("vm_clearFrontmatter")
    func vmClearFrontmatter() {
        let vm = FrontmatterViewModel()
        var text = """
        ---
        title: Hello
        ---
        body
        """

        vm.update(from: text)
        vm.frontmatter = Frontmatter()
        vm.apply(to: &text)

        #expect(text == "body")
    }

    @Test("compatibility_KMD66TagsExtraction")
    func compatibilityKMD66TagsExtraction() {
        let rendered = Frontmatter(tags: ["swift", "ios"]).render() + "body"
        let tags = TagsViewModel.extractTags(from: rendered)

        #expect(tags == Set(["swift", "ios"]))
    }
}
