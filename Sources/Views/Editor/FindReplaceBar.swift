import SwiftUI

struct FindReplaceBar: View {
    @Binding var isVisible: Bool
    @Binding var text: String

    @State private var findText: String = ""
    @State private var replaceText: String = ""
    @State private var matchCount: Int = 0
    @State private var currentMatch: Int = 0
    @State private var caseSensitive: Bool = false
    @FocusState private var isFindFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                TextField("Find...", text: $findText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .focused($isFindFieldFocused)
                    .onKeyPress(.return) {
                        nextMatch()
                        return .handled
                    }

                Button(action: { caseSensitive.toggle() }) {
                    Image(systemName: "textformat.abc")
                        .foregroundStyle(caseSensitive ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(caseSensitive ? "大文字小文字を区別する" : "大文字小文字を区別しない")
            }

            Text("\(currentMatch)/\(matchCount)")
                .foregroundStyle(matchCount == 0 && !findText.isEmpty ? .red : .secondary)
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
        .onChange(of: caseSensitive) { _, _ in refreshCount() }
        .onChange(of: isVisible) { _, visible in
            if visible { isFindFieldFocused = true }
        }
        .onExitCommand { isVisible = false }
        .onAppear { isFindFieldFocused = true }
    }

    private func findRanges() -> [Range<String.Index>] {
        guard !findText.isEmpty else { return [] }
        let options: String.CompareOptions = caseSensitive ? .literal : .caseInsensitive
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: findText, options: options, range: start..<text.endIndex) {
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
        nextMatch()
    }

    private func replaceAll() {
        guard !findText.isEmpty else { return }
        let options: String.CompareOptions = caseSensitive ? .literal : .caseInsensitive
        text = text.replacingOccurrences(of: findText, with: replaceText, options: options)
        matchCount = 0
        currentMatch = 0
    }
}
