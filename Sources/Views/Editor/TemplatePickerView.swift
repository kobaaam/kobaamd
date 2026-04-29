import SwiftUI
import AppKit

struct TemplatePickerView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Binding var isPresented: Bool

    @State private var templates: [DocumentTemplate] = []
    @State private var selectedTemplateID: String? = nil
    @State private var searchText: String = ""

    private var builtInTemplates: [DocumentTemplate] {
        templates.filter { $0.isBuiltIn }.filtered(by: searchText)
    }

    private var customTemplates: [DocumentTemplate] {
        templates.filter { !$0.isBuiltIn }.filtered(by: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("新規ドキュメント")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Search
            TextField("テンプレートを検索...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            Divider()

            // Template list
            List(selection: $selectedTemplateID) {
                // Empty file option
                Section {
                    TemplateRow(
                        title: "空ファイル",
                        description: "白紙のドキュメント",
                        isSelected: selectedTemplateID == "__empty__"
                    )
                    .tag("__empty__")
                    .onTapGesture { selectedTemplateID = "__empty__" }
                }

                if !builtInTemplates.isEmpty {
                    Section("ビルトイン") {
                        ForEach(builtInTemplates) { template in
                            TemplateRow(
                                title: template.title,
                                description: template.description,
                                isSelected: selectedTemplateID == template.id
                            )
                            .tag(template.id)
                            .onTapGesture { selectedTemplateID = template.id }
                        }
                    }
                }

                if !customTemplates.isEmpty {
                    Section("カスタム (\(customTemplates.count))") {
                        ForEach(customTemplates) { template in
                            TemplateRow(
                                title: template.title,
                                description: template.description,
                                isSelected: selectedTemplateID == template.id
                            )
                            .tag(template.id)
                            .onTapGesture { selectedTemplateID = template.id }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider()

            // Footer buttons
            HStack {
                Button("キャンセル") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("テンプレートフォルダを開く") {
                    NSWorkspace.shared.open(FileService.customTemplateDirectory)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.kobaMute)
                .font(.caption)

                Spacer()

                Button("作成") {
                    createDocument()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.kobaAccent)
                .disabled(selectedTemplateID == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 440, height: 360)
        .onAppear {
            templates = FileService().loadTemplates()
            selectedTemplateID = "__empty__"
        }
    }

    private func createDocument() {
        if selectedTemplateID == "__empty__" {
            appViewModel.newTab()
        } else if let template = templates.first(where: { $0.id == selectedTemplateID }) {
            appViewModel.newTabFromTemplate(content: template.content)
        }
        isPresented = false
    }
}

// MARK: - Template Row

private struct TemplateRow: View {
    let title: String
    let description: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.white : Color.kobaInk)
            if !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.kobaMute)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .listRowBackground(isSelected ? Color.kobaAccent.opacity(0.85) : Color.clear)
        .accessibilityLabel("\(title) \(description)")
    }
}

// MARK: - Filter extension

private extension Array where Element == DocumentTemplate {
    func filtered(by query: String) -> [DocumentTemplate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.description.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
