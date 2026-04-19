import SwiftUI

struct SettingsView: View {
    @State private var openAIKey:    String = APIKeyStore.load(for: .openai)    ?? ""
    @State private var anthropicKey: String = APIKeyStore.load(for: .anthropic) ?? ""
    @State private var saved: Bool = false

    var body: some View {
        Form {
            Section("AI プロバイダー") {
                LabeledContent("OpenAI API Key") {
                    SecureField("sk-...", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
                LabeledContent("Anthropic API Key") {
                    SecureField("sk-ant-...", text: $anthropicKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
            }

            Section {
                HStack {
                    Button("保存") {
                        APIKeyStore.save(openAIKey, for: .openai)
                        APIKeyStore.save(anthropicKey, for: .anthropic)
                        saved = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            saved = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(openAIKey.isEmpty && anthropicKey.isEmpty)

                    if saved {
                        Label("保存しました", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 260)
        .navigationTitle("設定")
    }
}
