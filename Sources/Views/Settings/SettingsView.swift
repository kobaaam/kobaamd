import SwiftUI

struct SettingsView: View {
    @State private var saved: Bool = false
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
                    Picker("", selection: $appState.selectedTheme) {
                        ForEach(ColorTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
                .onChange(of: appState.selectedTheme) { _, _ in
                    NotificationCenter.default.post(name: .e1TerminalAppearanceChanged, object: nil)
                }
                Text("ターミナル作業には Dark（#1e1e1e）を推奨。Gemini E1 設計と VS Code 系パレットに合わせています。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("コードフォント") {
                    HStack(spacing: 8) {
                        Button {
                            appState.adjustCodeFontSize(by: -AppState.CodeFontSize.step)
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(appState.terminalFontSize <= AppState.CodeFontSize.min)

                        Slider(
                            value: $appState.terminalFontSize,
                            in: AppState.CodeFontSize.min...AppState.CodeFontSize.max,
                            step: AppState.CodeFontSize.step
                        )
                        Text("\(Int(appState.terminalFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)

                        Button {
                            appState.adjustCodeFontSize(by: AppState.CodeFontSize.step)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(appState.terminalFontSize >= AppState.CodeFontSize.max)
                    }
                }
                .onChange(of: appState.terminalFontSize) { _, _ in
                    AppState.postCodeFontAppearanceChanged()
                }
                Text("ターミナルとエディタの等幅フォントサイズです。既定は 14pt（SF Mono）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Formatting") {
                Toggle("保存時に自動整形", isOn: $appState.autoFormatOnSave)
            }

            Section("E1 シェル") {
                Toggle("E1 シェル（Session | Terminal | Viewer）", isOn: $appState.useE1Shell)
                Text("Re-concept レイアウトです。OFF にすると従来の Markdown 3ペイン UI に戻ります。変更は再起動後に反映されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 480)
        .navigationTitle("設定")
    }
}