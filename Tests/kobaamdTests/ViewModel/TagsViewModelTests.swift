import Testing
@testable import kobaamd

@Suite("TagsViewModel")
struct TagsViewModelTests {
    @Test("Extract tags from frontmatter block list")
    func extractsTagsFromFrontmatterBlockList() {
        let text = """
        ---
        tags:
        - swift
        - ios
        ---
        body text
        """

        let tags = TagsViewModel.extractTags(from: text)

        #expect(tags == Set(["swift", "ios"]))
    }

    @Test("Extract tags from frontmatter inline array")
    func extractsTagsFromFrontmatterInlineArray() {
        let text = """
        ---
        tags: [swift, ios]
        ---
        body text
        """

        let tags = TagsViewModel.extractTags(from: text)

        #expect(tags == Set(["swift", "ios"]))
    }

    @Test("Extract inline hashtag tags without frontmatter")
    func extractsInlineHashtags() {
        let text = "some text #swift #ios more text"

        let tags = TagsViewModel.extractTags(from: text)

        #expect(tags == Set(["swift", "ios"]))
    }

    @Test("Heading markers are excluded but heading text is still scanned")
    func excludesHeadingMarkersButScansRemainingText() {
        let headingWithTag = "## Swift notes #swift"
        let headingWithoutTag = "## Swift notes"

        let tagsWithInlineTag = TagsViewModel.extractTags(from: headingWithTag)
        let tagsWithoutInlineTag = TagsViewModel.extractTags(from: headingWithoutTag)

        #expect(tagsWithInlineTag == Set(["swift"]))
        #expect(tagsWithoutInlineTag.isEmpty)
    }

    @Test("Ignore hashtags inside fenced code blocks")
    func ignoresHashtagsInsideCodeFences() {
        let text = """
        normal #real-tag
        ```
        code #fake-tag
        ```
        after fence #after-tag
        """

        let tags = TagsViewModel.extractTags(from: text)

        #expect(tags.contains("real-tag"))
        #expect(tags.contains("after-tag"))
        #expect(!tags.contains("fake-tag"))
        #expect(tags.count == 2)
    }

    @Test("Ignore URL fragments when extracting inline tags")
    func ignoresUrlFragments() {
        let text = "Visit https://example.com/page#section and #real"

        let tags = TagsViewModel.extractTags(from: text)

        #expect(tags.contains("real"))
        #expect(!tags.contains("section"))
        #expect(tags.count == 1)
    }
}
