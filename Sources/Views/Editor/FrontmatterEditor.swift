import Foundation
import SwiftUI
import Observation

struct FrontmatterEditor: View {
    @Binding var text: String
    @State private var vm = FrontmatterViewModel()

    var body: some View {
        Group {
            if vm.hasFrontmatter {
                if vm.isExpanded {
                    expandedPanel
                } else {
                    collapsedPanel
                }
            } else {
                addPanel
            }
        }
        .font(.system(size: 12))
        .background(Color.kobaSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.kobaLine)
                .frame(height: 1)
        }
        .onAppear {
            vm.update(from: text)
        }
        .onChange(of: text) { _, newText in
            vm.update(from: newText)
        }
    }

    private var addPanel: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                vm.insertTemplate(into: &text)
                vm.isExpanded = true
            } label: {
                Label("Add frontmatter", systemImage: "plus.rectangle.on.rectangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.kobaAccent)
            }
            .buttonStyle(.plain)

            Text("Insert frontmatter template")
                .foregroundStyle(Color.kobaMute)
                .font(.system(size: 12))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var collapsedPanel: some View {
        Button {
            vm.isExpanded = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kobaMute)

                Text("Frontmatter")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.kobaInk)

                Text("—")
                    .foregroundStyle(Color.kobaMute2)

                Text(titlePreview)
                    .foregroundStyle(Color.kobaMute)
                    .lineLimit(1)

                Spacer()

                Text("\(vm.frontmatter.tags.count) tags")
                    .foregroundStyle(Color.kobaMute)
                    .font(.system(size: 12))
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kobaMute)

                Text("Frontmatter")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.kobaInk)

                Spacer()

                Button {
                    vm.isExpanded = false
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.kobaMute)
                }
                .buttonStyle(.plain)
            }

            if let parseError = vm.frontmatter.parseError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(parseError)
                        .foregroundStyle(Color.kobaInk)
                        .lineLimit(nil)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            fieldRow("Title", text: stringBinding(
                get: { vm.frontmatter.title },
                set: { vm.frontmatter.title = $0 }
            ))

            fieldRow("Category", text: stringBinding(
                get: { vm.frontmatter.category },
                set: { vm.frontmatter.category = $0 }
            ))

            fieldRow("Tags", text: csvBinding(
                get: { vm.frontmatter.tags },
                set: { vm.frontmatter.tags = $0 }
            ), prompt: "swift, ios")

            fieldRow("Aliases", text: csvBinding(
                get: { vm.frontmatter.aliases },
                set: { vm.frontmatter.aliases = $0 }
            ), prompt: "short-name, alternate-name")

            fieldRow("Date", text: stringBinding(
                get: { vm.frontmatter.date },
                set: { vm.frontmatter.date = $0 }
            ), prompt: "2026-05-09T12:00:00Z")

            fieldRow("Description", text: stringBinding(
                get: { vm.frontmatter.description },
                set: { vm.frontmatter.description = $0 }
            ))

            if !vm.frontmatter.extraLines.isEmpty {
                Text("Other fields preserved (not editable here): \(vm.frontmatter.extraLines.count) lines")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var titlePreview: String {
        let title = vm.frontmatter.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Untitled" : title
    }

    private func fieldRow(_ label: String, text: Binding<String>, prompt: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(Color.kobaMute)
                .frame(width: 72, alignment: .leading)

            TextField(
                label,
                text: text,
                prompt: prompt.map(Text.init)
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit {
                vm.apply(to: &self.text)
            }
        }
    }

    private func stringBinding(get: @escaping () -> String?, set: @escaping (String?) -> Void) -> Binding<String> {
        Binding(
            get: { get() ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                set(trimmed.isEmpty ? nil : trimmed)
                vm.apply(to: &text)
            }
        )
    }

    private func csvBinding(get: @escaping () -> [String], set: @escaping ([String]) -> Void) -> Binding<String> {
        Binding(
            get: { get().joined(separator: ", ") },
            set: { newValue in
                let values = newValue
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                set(values)
                vm.apply(to: &text)
            }
        )
    }
}
