import Foundation

struct MarkdownFormatterService {
    func format(_ text: String) -> (result: String, changeCount: Int) {
        let originalLines = text.components(separatedBy: "\n")
        let resultLines = formatLines(originalLines)
        let result = resultLines.joined(separator: "\n")

        let lineChanges = zip(originalLines, resultLines).reduce(0) { partialResult, pair in
            partialResult + (pair.0 == pair.1 ? 0 : 1)
        } + abs(originalLines.count - resultLines.count)

        let changeCount = text == result ? 0 : max(1, lineChanges)
        return (result, changeCount)
    }

    private func formatLines(_ lines: [String]) -> [String] {
        var formatted: [String] = []
        var insideCodeBlock = false
        var activeFenceCharacter: Character?
        var pendingBlankAfterHeading = false

        for line in lines {
            if insideCodeBlock {
                if let fence = parseFence(in: line), fence.character == activeFenceCharacter {
                    formatted.append(fence.normalizedLine)
                    insideCodeBlock = false
                    activeFenceCharacter = nil
                } else {
                    formatted.append(line)
                }
                continue
            }

            if let fence = parseFence(in: line) {
                if pendingBlankAfterHeading, !endsWithBlankLine(formatted) {
                    formatted.append("")
                }
                pendingBlankAfterHeading = false
                formatted.append(fence.normalizedLine)
                insideCodeBlock = true
                activeFenceCharacter = fence.character
                continue
            }

            let trimmedLine = trimmingTrailingWhitespace(in: line)
            let isBlankLine = trimmedLine.isEmpty

            if pendingBlankAfterHeading {
                if !endsWithBlankLine(formatted) {
                    formatted.append("")
                }
                pendingBlankAfterHeading = false
                if isBlankLine {
                    continue
                }
            }

            if isHeadingLine(trimmedLine) {
                if !formatted.isEmpty {
                    while endsWithBlankLine(formatted) {
                        formatted.removeLast()
                    }
                    formatted.append("")
                }
                formatted.append(trimmedLine)
                pendingBlankAfterHeading = true
                continue
            }

            if isBlankLine {
                if trailingBlankLineCount(in: formatted) < 2 {
                    formatted.append("")
                }
                continue
            }

            formatted.append(trimmedLine)
        }

        if pendingBlankAfterHeading, !endsWithBlankLine(formatted) {
            formatted.append("")
        }

        return formatted
    }

    private func trimmingTrailingWhitespace(in line: String) -> String {
        var endIndex = line.endIndex

        while endIndex > line.startIndex {
            let previousIndex = line.index(before: endIndex)
            let character = line[previousIndex]
            if character == " " || character == "\t" {
                endIndex = previousIndex
            } else {
                break
            }
        }

        return String(line[..<endIndex])
    }

    private func isHeadingLine(_ line: String) -> Bool {
        line.first == "#"
    }

    private func trailingBlankLineCount(in lines: [String]) -> Int {
        var count = 0

        for line in lines.reversed() where line.isEmpty {
            count += 1
        }

        return count
    }

    private func endsWithBlankLine(_ lines: [String]) -> Bool {
        lines.last?.isEmpty == true
    }

    private func parseFence(in line: String) -> (character: Character, normalizedLine: String)? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmedLeading = String(line.dropFirst(indent.count))

        guard let marker = trimmedLeading.first, marker == "`" || marker == "~" else {
            return nil
        }

        let fencePrefix = trimmedLeading.prefix { $0 == marker }
        guard fencePrefix.count >= 3 else { return nil }

        let suffix = trimmedLeading.dropFirst(fencePrefix.count)
        return (marker, indent + "```" + suffix)
    }
}
