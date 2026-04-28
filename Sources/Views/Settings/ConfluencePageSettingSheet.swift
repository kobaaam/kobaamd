import SwiftUI

struct ConfluencePageSettingSheet: View {
    let fileURL: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(ConfluenceSyncViewModel.self) private var confluenceVM

    @State private var spaceKey: String = ""
    @State private var parentPageId: String = ""
    @State private var pageTitle: String = ""
    @State private var existingPageId: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Confluence ページ設定")
                .font(.headline)
                .padding(.bottom, 16)

            Form {
                LabeledContent("対象ファイル") {
                    Text(fileURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Space Key") {
                    TextField("例: ENG", text: $spaceKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }

                LabeledContent("Parent Page ID") {
                    TextField("省略可", text: $parentPageId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }

                LabeledContent("Page Title") {
                    TextField("ページタイトル", text: $pageTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }

                if !existingPageId.isEmpty {
                    LabeledContent("Page ID") {
                        Text(existingPageId)
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(spaceKey.isEmpty || pageTitle.isEmpty)
                    .keyboardShortcut(.return)
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 480, height: 340)
        .onAppear { loadExisting() }
        .alert("保存エラー", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadExisting() {
        if let mapping = confluenceVM.loadMapping(for: fileURL) {
            spaceKey = mapping.spaceKey
            parentPageId = mapping.parentPageId ?? ""
            pageTitle = mapping.pageTitle
            existingPageId = mapping.pageId ?? ""
        } else {
            pageTitle = fileURL.deletingPathExtension().lastPathComponent
        }
    }

    private func save() {
        let mapping = ConfluenceService.PageMapping(
            spaceKey: spaceKey,
            parentPageId: parentPageId.isEmpty ? nil : parentPageId,
            pageTitle: pageTitle,
            pageId: existingPageId.isEmpty ? nil : existingPageId
        )
        do {
            try confluenceVM.saveMapping(mapping, for: fileURL)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
