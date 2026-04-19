import SwiftUI

struct AIAssistPanel: View {
    @Binding var isVisible: Bool
    @Binding var editorText: String

    @State private var prompt:   String = ""
    @State private var provider: APIKeyStore.Provider = .openai
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var result:  String = ""
    @State private var showResult: Bool = false

    private let service = AIService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.kobaAccent)
                Text("AI アシスト")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kobaInk)
                Spacer()
                Picker("", selection: $provider) {
                    ForEach(APIKeyStore.Provider.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                Button { isVisible = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.kobaMute)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.kobaSurface)
            .overlay(Rectangle().fill(Color.kobaLine).frame(height: 1), alignment: .bottom)

            // Prompt input
            HStack(spacing: 8) {
                TextField("プロンプトを入力 (例: 箇条書きをまとめて)", text: $prompt, axis: .vertical)
                    .lineLimit(3)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await run() } }

                Button {
                    Task { await run() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(prompt.isEmpty ? Color.kobaMute : Color.kobaAccent)
                    }
                }
                .buttonStyle(.plain)
                .disabled(prompt.isEmpty || isLoading)
            }
            .padding(10)

            // Error
            if let err = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kobaMute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Result
            if showResult && !result.isEmpty {
                Divider()
                ScrollView {
                    Text(result)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.kobaInk)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 200)

                HStack(spacing: 8) {
                    Button("エディタに追記") {
                        editorText += "\n\n" + result
                        isVisible = false
                    }
                    .buttonStyle(.bordered)
                    Button("エディタを置き換え") {
                        editorText = result
                        isVisible = false
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Button("コピー") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(Color.kobaPaper)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .onExitCommand { isVisible = false }
    }

    @MainActor
    private func run() async {
        guard !prompt.isEmpty else { return }
        errorMessage = nil
        result = ""
        showResult = false
        isLoading = true
        defer { isLoading = false }

        do {
            result = try await service.complete(
                prompt: prompt,
                context: editorText,
                provider: provider
            )
            showResult = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
