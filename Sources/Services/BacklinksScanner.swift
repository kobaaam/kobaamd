import Foundation

struct BacklinksScanner: Sendable {
    static func scan(
        sourceURL: URL,
        sourceContent: String,
        targetURL: URL
    ) -> (linked: [Backlink], unlinked: [Backlink]) {
        guard sourceURL != targetURL else {
            return ([], [])
        }

        let basename = targetURL.deletingPathExtension().lastPathComponent
        guard !basename.isEmpty else {
            return ([], [])
        }

        let nsContent = sourceContent as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let escapedBase = NSRegularExpression.escapedPattern(for: basename)

        let linkedPatterns = [
            "(?i)\\[\\[\\s*\(escapedBase)(?:[#|][^\\]]*)?\\s*\\]\\]",
            "(?i)\\]\\(\\s*(?:\\./)?(?:[^)\\s]+/)*\(escapedBase)(?:\\.[a-zA-Z0-9]+)?(?:#[^)]*)?\\s*\\)"
        ]

        var linked: [Backlink] = []
        var linkedRanges: [NSRange] = []

        for patternTemplate in linkedPatterns {
            guard let regex = try? NSRegularExpression(pattern: patternTemplate) else { continue }

            for match in regex.matches(in: sourceContent, range: fullRange) {
                let range = match.range
                guard range.location != NSNotFound, range.length > 0 else { continue }

                linkedRanges.append(range)
                linked.append(
                    Backlink(
                        sourceURL: sourceURL,
                        line: lineNumber(for: range.location, in: nsContent),
                        kind: .linked,
                        snippet: snippet(for: range, matchedText: nsContent.substring(with: range), in: nsContent),
                        matchRange: range,
                        matchedText: nsContent.substring(with: range)
                    )
                )
            }
        }

        guard basename.count >= 3 else {
            return (linked.sorted(by: backlinkSort), [])
        }

        let unlinkedPattern = "(?i)(?<![\\w/.\\[])\(escapedBase)(?![\\w.\\]])"

        guard let unlinkedRegex = try? NSRegularExpression(pattern: unlinkedPattern) else {
            return (linked.sorted(by: backlinkSort), [])
        }

        var unlinked: [Backlink] = []
        for match in unlinkedRegex.matches(in: sourceContent, range: fullRange) {
            let range = match.range
            guard range.location != NSNotFound, range.length > 0 else { continue }
            guard !linkedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { continue }

            let matchedText = nsContent.substring(with: range)
            unlinked.append(
                Backlink(
                    sourceURL: sourceURL,
                    line: lineNumber(for: range.location, in: nsContent),
                    kind: .unlinked,
                    snippet: snippet(for: range, matchedText: matchedText, in: nsContent),
                    matchRange: range,
                    matchedText: matchedText
                )
            )
        }

        return (linked.sorted(by: backlinkSort), unlinked.sorted(by: backlinkSort))
    }

    static func convertToLink(
        sourceContent: String,
        range: NSRange,
        targetURL: URL
    ) -> String {
        let basename = targetURL.deletingPathExtension().lastPathComponent
        guard !basename.isEmpty,
              let swiftRange = Range(range, in: sourceContent) else {
            return sourceContent
        }

        var content = sourceContent
        content.replaceSubrange(swiftRange, with: "[[\(basename)]]")
        return content
    }

    private static func lineNumber(for location: Int, in content: NSString) -> Int {
        guard location > 0 else { return 1 }
        let prefix = content.substring(to: min(location, content.length))
        return prefix.reduce(into: 1) { line, character in
            if character == "\n" {
                line += 1
            }
        }
    }

    private static func snippet(for range: NSRange, matchedText: String, in content: NSString) -> String {
        let beforeStart = max(0, range.location - 30)
        let beforeRange = NSRange(location: beforeStart, length: range.location - beforeStart)
        let afterStart = range.location + range.length
        let afterEnd = min(content.length, afterStart + 30)
        let afterRange = NSRange(location: afterStart, length: afterEnd - afterStart)

        let before = content.substring(with: beforeRange)
        let after = content.substring(with: afterRange)

        return [
            beforeStart > 0 ? "..." : "",
            before,
            matchedText,
            after,
            afterEnd < content.length ? "..." : ""
        ].joined()
    }

    private static func backlinkSort(lhs: Backlink, rhs: Backlink) -> Bool {
        if lhs.sourceURL.path != rhs.sourceURL.path {
            return lhs.sourceURL.path.localizedCaseInsensitiveCompare(rhs.sourceURL.path) == .orderedAscending
        }
        return lhs.matchRange.location < rhs.matchRange.location
    }
}
