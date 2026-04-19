import SwiftUI

struct FindReplaceBar: View {
    @Binding var isVisible: Bool
    @Binding var text: String

    @State private var findText: String = ""
    @State private var replaceText: String = ""
    @State private var matchCount: Int = 0
    @State private var currentMatch: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find...", text: $findText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            Text("\(currentMatch)/\(matchCount)")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(width: 50)

            Button(action: prevMatch) { Image(systemName: "chevron.up") }
                .disabled(matchCount == 0)
            Button(action: nextMatch) { Image(systemName: "chevron.down") }
                .disabled(matchCount == 0)

            Divider()

            TextField("Replace...", text: $replaceText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            Button("Replace") { replaceOne() }
                .disabled(matchCount == 0 || findText.isEmpty)
            Button("All") { replaceAll() }
                .disabled(findText.isEmpty)

            Spacer()

            Button { isVisible = false } label: { Image(systemName: "xmark") }
        }
        .padding(6)
        .background(.bar)
        .onChange(of: findText) { _, _ in refreshCount() }
        .onChange(of: text) { _, _ in refreshCount() }
    }

    private func findRanges() -> [Range<String.Index>] {
        guard !findText.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: findText, options: .caseInsensitive, range: start..<text.endIndex) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }

    private func refreshCount() {
        let ranges = findRanges()
        matchCount = ranges.count
        currentMatch = matchCount > 0 ? min(max(currentMatch, 1), matchCount) : 0
    }

    private func prevMatch() {
        guard matchCount > 0 else { return }
        currentMatch = currentMatch <= 1 ? matchCount : currentMatch - 1
    }

    private func nextMatch() {
        guard matchCount > 0 else { return }
        currentMatch = currentMatch >= matchCount ? 1 : currentMatch + 1
    }

    private func replaceOne() {
        let ranges = findRanges()
        guard !ranges.isEmpty else { return }
        let idx = min(max(currentMatch - 1, 0), ranges.count - 1)
        text.replaceSubrange(ranges[idx], with: replaceText)
        refreshCount()
    }

    private func replaceAll() {
        guard !findText.isEmpty else { return }
        text = text.replacingOccurrences(of: findText, with: replaceText, options: .caseInsensitive)
        matchCount = 0
        currentMatch = 0
    }
}
