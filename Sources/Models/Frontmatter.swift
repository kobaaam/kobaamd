import Foundation

struct Frontmatter: Equatable {
    var title: String? = nil
    var category: String? = nil
    var tags: [String] = []
    var aliases: [String] = []
    var date: String? = nil
    var description: String? = nil
    var extraLines: [String] = []
    var parseError: String? = nil

    private static let nestedValueWarning = "Nested values not editable; preserved as raw lines."

    static func split(text: String) -> (frontmatterText: String?, body: String, leadingBlankLine: Bool) {
        let normalized = normalizeLineEndings(in: text)
        let lines = normalized.components(separatedBy: "\n")

        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return (nil, normalized, false)
        }

        var endIndex: Int? = nil
        for index in 1..<lines.count where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
            endIndex = index
            break
        }

        guard let endIndex else {
            return (nil, normalized, false)
        }

        let frontmatterText = lines[1..<endIndex].joined(separator: "\n")
        let body = endIndex + 1 < lines.count ? lines[(endIndex + 1)...].joined(separator: "\n") : ""
        return (frontmatterText, body, body.hasPrefix("\n"))
    }

    static func parse(yaml: String) -> Frontmatter {
        let normalized = normalizeLineEndings(in: yaml)
        let lines = normalized.components(separatedBy: "\n")
        var frontmatter = Frontmatter()
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                frontmatter.extraLines.append(rawLine)
                index += 1
                continue
            }

            if indentation(of: rawLine) > 0 {
                frontmatter.extraLines.append(rawLine)
                index += 1
                continue
            }

            guard let colonIndex = rawLine.firstIndex(of: ":") else {
                frontmatter.extraLines.append(rawLine)
                index += 1
                continue
            }

            let key = rawLine[..<colonIndex].trimmingCharacters(in: .whitespaces)
            let valueStart = rawLine.index(after: colonIndex)
            let rawValue = String(rawLine[valueStart...]).trimmingCharacters(in: .whitespaces)
            let nestedBlock = consumeNestedBlock(lines: lines, startingAt: index + 1, parentIndent: indentation(of: rawLine))

            switch key {
            case "title":
                if nestedBlock.lines.isEmpty {
                    frontmatter.title = normalizedScalar(rawValue)
                    index += 1
                } else {
                    frontmatter.recordNestedWarning()
                    frontmatter.extraLines.append(rawLine)
                    frontmatter.extraLines.append(contentsOf: nestedBlock.lines)
                    index = nestedBlock.nextIndex
                }

            case "category":
                if nestedBlock.lines.isEmpty {
                    frontmatter.category = normalizedScalar(rawValue)
                    index += 1
                } else {
                    frontmatter.recordNestedWarning()
                    frontmatter.extraLines.append(rawLine)
                    frontmatter.extraLines.append(contentsOf: nestedBlock.lines)
                    index = nestedBlock.nextIndex
                }

            case "date":
                if nestedBlock.lines.isEmpty {
                    frontmatter.date = normalizedScalar(rawValue)
                    index += 1
                } else {
                    frontmatter.recordNestedWarning()
                    frontmatter.extraLines.append(rawLine)
                    frontmatter.extraLines.append(contentsOf: nestedBlock.lines)
                    index = nestedBlock.nextIndex
                }

            case "description":
                if nestedBlock.lines.isEmpty {
                    frontmatter.description = normalizedScalar(rawValue)
                    index += 1
                } else {
                    frontmatter.recordNestedWarning()
                    frontmatter.extraLines.append(rawLine)
                    frontmatter.extraLines.append(contentsOf: nestedBlock.lines)
                    index = nestedBlock.nextIndex
                }

            case "tags":
                if !nestedBlock.lines.isEmpty {
                    if let parsedList = parseListBlock(nestedBlock.lines) {
                        frontmatter.tags = parsedList
                    } else {
                        frontmatter.recordNestedWarning()
                        frontmatter.extraLines.append(rawLine)
                        frontmatter.extraLines.append(contentsOf: nestedBlock.lines)
                    }
                    index = nestedBlock.nextIndex
                } else {
                    frontmatter.tags = parseInlineListOrScalar(rawValue)
                    index += 1
                }

            case "aliases":
                if !nestedBlock.lines.isEmpty {
                    if let parsedList = parseListBlock(nestedBlock.lines) {
                        frontmatter.aliases = parsedList
                    } else {
                        frontmatter.recordNestedWarning()
                        frontmatter.extraLines.append(rawLine)
                        frontmatter.extraLines.append(contentsOf: nestedBlock.lines)
                    }
                    index = nestedBlock.nextIndex
                } else {
                    frontmatter.aliases = parseInlineListOrScalar(rawValue)
                    index += 1
                }

            default:
                if nestedBlock.lines.isEmpty {
                    frontmatter.extraLines.append(rawLine)
                    index += 1
                } else {
                    frontmatter.recordNestedWarning()
                    frontmatter.extraLines.append(rawLine)
                    frontmatter.extraLines.append(contentsOf: nestedBlock.lines)
                    index = nestedBlock.nextIndex
                }
            }
        }

        return frontmatter
    }

    func render() -> String {
        var lines: [String] = []

        if let title = Self.normalizedOutput(title) {
            lines.append("title: \(Self.yamlScalar(title))")
        }
        if let category = Self.normalizedOutput(category) {
            lines.append("category: \(Self.yamlScalar(category))")
        }
        let renderedTags = tags.compactMap { item -> String? in
            guard let value = Self.normalizedOutput(item) else { return nil }
            return "  - \(Self.yamlScalar(value))"
        }
        if !renderedTags.isEmpty {
            lines.append("tags:")
            lines.append(contentsOf: renderedTags)
        }
        let renderedAliases = aliases.compactMap { item -> String? in
            guard let value = Self.normalizedOutput(item) else { return nil }
            return "  - \(Self.yamlScalar(value))"
        }
        if !renderedAliases.isEmpty {
            lines.append("aliases:")
            lines.append(contentsOf: renderedAliases)
        }
        if let date = Self.normalizedOutput(date) {
            lines.append("date: \(Self.yamlScalar(date))")
        }
        if let description = Self.normalizedOutput(description) {
            lines.append("description: \(Self.yamlScalar(description))")
        }

        lines.append(contentsOf: extraLines)

        if lines.isEmpty {
            return ""
        }

        return """
        ---
        \(lines.joined(separator: "\n"))
        ---
        """
        + "\n"
    }

    static func template() -> String {
        """
        ---
        title:
        tags:
        ---
        """
        + "\n"
    }

    private mutating func recordNestedWarning() {
        if parseError == nil {
            parseError = Self.nestedValueWarning
        }
    }

    private static func normalizeLineEndings(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func indentation(of line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private static func normalizedScalar(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return unquote(trimmed)
    }

    private static func normalizedOutput(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseInlineListOrScalar(_ rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = String(trimmed.dropFirst().dropLast())
            return inner
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.isEmpty }
        }

        return trimmed
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func parseListBlock(_ lines: [String]) -> [String]? {
        var items: [String] = []

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }
            guard trimmed.hasPrefix("- ") else {
                return nil
            }
            let value = unquote(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            if !value.isEmpty {
                items.append(value)
            }
        }

        return items
    }

    private static func consumeNestedBlock(
        lines: [String],
        startingAt startIndex: Int,
        parentIndent: Int
    ) -> (lines: [String], nextIndex: Int) {
        guard startIndex < lines.count else {
            return ([], startIndex)
        }

        var collected: [String] = []
        var sawIndentedLine = false
        var index = startIndex

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if sawIndentedLine {
                    collected.append(line)
                    index += 1
                    continue
                }
                break
            }

            let indent = indentation(of: line)
            if indent > parentIndent {
                sawIndentedLine = true
                collected.append(line)
                index += 1
                continue
            }

            break
        }

        return (collected, index)
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func yamlScalar(_ value: String) -> String {
        if value.isEmpty {
            return "\"\""
        }

        let needsQuotes =
            value != value.trimmingCharacters(in: .whitespaces) ||
            value.contains(":") ||
            value.contains("#") ||
            value.contains("[") ||
            value.contains("]") ||
            value.contains("{") ||
            value.contains("}") ||
            value.contains(",") ||
            value.contains("\"")

        guard needsQuotes else { return value }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
