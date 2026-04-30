import SwiftUI

struct AIInlinePopover: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var prompt: String = ""
    @State private var errorMessage: String? = nil
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.kobaAccent)
                    .font(.system(size: 14))

                TextField("AI に指示...", text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isPromptFocused)
                    .onSubmit {
                        submitPrompt()
                    }

                Button {
                    submitPrompt()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(prompt.isEmpty ? Color.kobaMute : Color.kobaAccent)
                }
                .buttonStyle(.plain)
                .disabled(prompt.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let error = errorMessage {
                Rectangle().fill(Color.kobaLine).frame(height: 1)
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kobaMute)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            Rectangle().fill(Color.kobaLine).frame(height: 1)
            Text("Enter: 送信  Esc: キャンセル")
                .font(.caption2)
                .foregroundStyle(Color.kobaMute2)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
        .frame(width: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.kobaLine.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .onAppear {
            // API キーチェック
            let hasOpenAI = APIKeyStore.load(for: .openai).map { !$0.isEmpty } ?? false
            let hasAnthropic = APIKeyStore.load(for: .anthropic).map { !$0.isEmpty } ?? false
            if !hasOpenAI && !hasAnthropic {
                errorMessage = "API キーが設定されていません（設定 ⌘, から登録）"
            }
            isPromptFocused = true
        }
        .onExitCommand {
            appViewModel.isAIInlinePromptVisible = false
        }
    }

    private func submitPrompt() {
        guard !prompt.isEmpty else { return }
        let hasOpenAI = APIKeyStore.load(for: .openai).map { !$0.isEmpty } ?? false
        let hasAnthropic = APIKeyStore.load(for: .anthropic).map { !$0.isEmpty } ?? false
        guard hasOpenAI || hasAnthropic else {
            errorMessage = "API キーが設定されていません（設定 ⌘, から登録）"
            return
        }
        appViewModel.startAIInlineFromSpace(prompt: prompt)
    }
}
