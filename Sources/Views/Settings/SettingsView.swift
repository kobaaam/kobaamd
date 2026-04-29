import SwiftUI
import Sparkle

struct SettingsView: View {
    let updater: SPUUpdater

    @State private var openAIKey:       String = APIKeyStore.load(for: .openai)          ?? ""
    @State private var anthropicKey:    String = APIKeyStore.load(for: .anthropic)       ?? ""
    @State private var confluenceURL:   String = APIKeyStore.load(for: .confluenceURL)   ?? ""
    @State private var confluenceEmail: String = APIKeyStore.load(for: .confluenceEmail) ?? ""
    @State private var confluenceToken: String = APIKeyStore.load(for: .confluenceToken) ?? ""
    @State private var saved: Bool = false
    @State private var connectionTestResult: String? = nil
    @Environment(AppViewModel.self) private var appViewModel
    @State private var snippetTitle: String = ""
    @State private var snippetPrompt: String = ""
    private var canAddSnippet: Bool {
        !snippetTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !snippetPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        @Bindable var appState = AppState.shared

        Form {
            Section("外観") {
                LabeledContent("テーマ") {
                    Picker("", selection: Binding(
                        get: { AppState.shared.selectedTheme },
                        set: { AppState.shared.selectedTheme = $0 }
                    )) {
                        ForEach(ColorTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
            }

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

            Section("アップデート") {
                LabeledContent("自動確認") {
                    Picker("", selection: Binding(
                        get: { AppState.shared.updateCheckInterval },
                        set: { AppState.shared.updateCheckInterval = $0 }
                    )) {
                        Text("起動時のみ").tag(UpdateCheckInterval.atLaunch)
                        Text("毎日").tag(UpdateCheckInterval.daily)
                        Text("毎週").tag(UpdateCheckInterval.weekly)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                CheckForUpdatesView(updater: updater)
            }

            Section("Formatting") {
                Toggle("保存時に自動整形", isOn: $appState.autoFormatOnSave)
            }

            Section("テンプレート") {
                HStack {
                    Text("カスタムテンプレートフォルダ")
                    Spacer()
                    Button("Finder で開く") {
                        FileService().ensureCustomTemplateDirectory()
                        NSWorkspace.shared.open(FileService.customTemplateDirectory)
                    }
                }
                Text("~/.config/kobaamd/templates/ に .md ファイルを追加すると、新規ドキュメント作成時にテンプレートとして利用できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("クイックインサート テンプレート") {
                if appViewModel.snippetStore.customSnippets.isEmpty {
                    Text("カスタムテンプレートはまだありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appViewModel.snippetStore.customSnippets) { snippet in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snippet.title)
                                Text(snippet.prompt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                appViewModel.snippetStore.removeCustom(id: snippet.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                TextField("タイトル", text: $snippetTitle)
                TextField("プロンプト", text: $snippetPrompt, axis: .vertical)
                    .lineLimit(2...4)

                Button("+ 追加") {
                    appViewModel.snippetStore.addCustom(title: snippetTitle, prompt: snippetPrompt)
                    snippetTitle = ""
                    snippetPrompt = ""
                }
                .disabled(!canAddSnippet)
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
                    // Confluence 機能のみ使用するユーザーへの対応として confluence token も条件に含める（PRD section 3-1 対応）
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
        .frame(width: 520, height: 560)
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
