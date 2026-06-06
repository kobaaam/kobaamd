import SwiftUI

// MARK: - E1 editor status bar

struct E1EditorStatusBar: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable private var appState = AppState.shared

    private var charCount: Int { appViewModel.editorText.count }

    var body: some View {
        let chrome = appState.selectedTheme
        HStack(spacing: 12) {
            if let url = appViewModel.selectedFileURL {
                Text(url.lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(chrome.chromeMute)
                    .lineLimit(1)
            }

            Spacer()

            if appViewModel.lineCount > 0 {
                statLabel("Ln \(appViewModel.lineCount)")
                statLabel("\(appViewModel.wordCount) words")
                statLabel("\(charCount) chars")
            }

            if appViewModel.isDirty {
                Circle()
                    .fill(Color.kobaAccent)
                    .frame(width: 5, height: 5)
                    .help("未保存の変更あり")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(chrome.chromeSurface)
        .overlay(KobaHDivider(), alignment: .top)
    }

    private func statLabel(_ text: String) -> some View {
        let chrome = appState.selectedTheme
        return Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(chrome.chromeMute2)
    }
}