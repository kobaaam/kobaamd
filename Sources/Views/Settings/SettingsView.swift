import SwiftUI
import Sparkle

struct SettingsView: View {
    let updater: SPUUpdater

    @State private var openAIKey:    String = APIKeyStore.load(for: .openai)    ?? ""
    @State private var anthropicKey: String = APIKeyStore.load(for: .anthropic) ?? ""
    @State private var saved: Bool = false

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
        .frame(width: 520, height: 400)
        .navigationTitle("設定")
    }
}
