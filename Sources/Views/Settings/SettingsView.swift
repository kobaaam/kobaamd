import SwiftUI

struct SettingsView: View {
    @State private var openAIKey:       String = APIKeyStore.load(for: .openai)          ?? ""
    @State private var anthropicKey:    String = APIKeyStore.load(for: .anthropic)       ?? ""
    @State private var confluenceURL:   String = APIKeyStore.load(for: .confluenceURL)   ?? ""
    @State private var confluenceEmail: String = APIKeyStore.load(for: .confluenceEmail) ?? ""
    @State private var confluenceToken: String = APIKeyStore.load(for: .confluenceToken) ?? ""
    @State private var saved: Bool = false
    @State private var connectionTestResult: String? = nil

    var body: some View {
        @Bindable var appState = AppState.shared

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

            Section("Confluence") {
                LabeledContent("Base URL") {
                    TextField("https://yoursite.atlassian.net", text: $confluenceURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
                LabeledContent("Email") {
                    TextField("user@example.com", text: $confluenceEmail)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
                LabeledContent("API Token") {
                    SecureField("token", text: $confluenceToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
                HStack {
                    Button("接続テスト") {
                        Task { await testConfluenceConnection() }
                    }
                    .disabled(confluenceURL.isEmpty || confluenceEmail.isEmpty || confluenceToken.isEmpty)
                    if let msg = connectionTestResult {
                        Text(msg)
                            .foregroundStyle(msg.hasPrefix("接続OK") ? Color.green : Color.red)
                            .font(.caption)
                    }
                }
            }

            Section("Formatting") {
                Toggle("保存時に自動整形", isOn: $appState.autoFormatOnSave)
            }

            Section {
                HStack {
                    Button("保存") {
                        APIKeyStore.save(openAIKey,       for: .openai)
                        APIKeyStore.save(anthropicKey,    for: .anthropic)
                        APIKeyStore.save(confluenceURL,   for: .confluenceURL)
                        APIKeyStore.save(confluenceEmail, for: .confluenceEmail)
                        APIKeyStore.save(confluenceToken, for: .confluenceToken)
                        saved = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            saved = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(openAIKey.isEmpty && anthropicKey.isEmpty && confluenceToken.isEmpty)

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
        .frame(width: 520, height: 480)
        .navigationTitle("設定")
    }

    private func testConfluenceConnection() async {
        connectionTestResult = "テスト中..."
        do {
            let ok = try await ConfluenceService().testConnection(
                baseURL: confluenceURL, email: confluenceEmail, apiToken: confluenceToken)
            let date = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            connectionTestResult = ok ? "接続OK (\(date))" : "接続失敗"
        } catch {
            connectionTestResult = "エラー: \(error.localizedDescription)"
        }
    }
}
