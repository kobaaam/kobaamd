import SwiftUI
import AppKit

struct TodoView: View {
    @Environment(AppViewModel.self) private var appViewModel
    let todoViewModel: TodoViewModel
    @State private var hoveredID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            scopePicker
            content
        }
        .background(Color.kobaSidebar)
    }

    private var scopePicker: some View {
        Picker("Scope", selection: Binding(
            get: { todoViewModel.scope },
            set: { todoViewModel.setScope($0) }
        )) {
            ForEach(TodoScope.allCases) { scope in
                Text(scope.label).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .accessibilityLabel("TODO 表示スコープ")
    }

    @ViewBuilder
    private var content: some View {
        if todoViewModel.isScanning && todoViewModel.items.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("スキャン中…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
                    .padding(.top, 6)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if todoViewModel.items.isEmpty {
            VStack {
                Spacer()
                Text("TODO が見つかりません")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kobaMute)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if todoViewModel.scope == .file {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(todoViewModel.items) { item in
                        todoRow(item)
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            groupedContent
        }
    }

    private var groupedContent: some View {
        let grouped = Dictionary(grouping: todoViewModel.items) { $0.fileURL?.path ?? "" }
        let keys = grouped.keys.sorted()

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(keys, id: \.self) { key in
                    if let items = grouped[key], !items.isEmpty {
                        groupHeader(for: items.first?.fileURL)
                        ForEach(items) { item in
                            todoRow(item)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func groupHeader(for url: URL?) -> some View {
        Text(relativePath(for: url))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.kobaMute)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func relativePath(for url: URL?) -> String {
        guard let url else { return "(unsaved)" }
        for folder in appViewModel.fileTreeViewModel.folders {
            let rootPath = folder.url.path
            if url.path.hasPrefix(rootPath + "/") {
                let relative = String(url.path.dropFirst(rootPath.count + 1))
                return "\(folder.url.lastPathComponent)/\(relative)"
            }
        }
        return url.lastPathComponent
    }

    @ViewBuilder
    private func todoRow(_ item: TodoItem) -> some View {
        let badgeColor = item.label == "FIXME" ? Color.orange : Color.kobaAccent

        HStack(spacing: 8) {
            Text(item.label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(badgeColor.opacity(0.12))
                )

            Text("L" + String(item.line))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.kobaMute)

            Text(item.text)
                .font(.system(size: 12))
                .foregroundStyle(Color.kobaInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(
            hoveredID == item.id
                ? Color.kobaInk.opacity(0.06)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredID = hovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .onTapGesture {
            handleTap(item)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: item))
    }

    private func accessibilityLabel(for item: TodoItem) -> String {
        if let fileURL = item.fileURL {
            return "\(item.label) \(item.text) \(fileURL.lastPathComponent) \(item.line)行目"
        }
        return "\(item.label) \(item.text) \(item.line)行目"
    }

    private func handleTap(_ item: TodoItem) {
        if let url = item.fileURL {
            Task { @MainActor in
                await appViewModel.openFile(url: url)
                try? await Task.sleep(for: .milliseconds(200))
                NotificationCenter.default.post(
                    name: .jumpToLine,
                    object: nil,
                    userInfo: ["line": item.line]
                )
            }
        } else {
            NotificationCenter.default.post(
                name: .jumpToLine,
                object: nil,
                userInfo: ["line": item.line]
            )
        }
    }
}
