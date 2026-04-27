import SwiftUI
import AppKit

struct QuickInsertView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Binding var isVisible: Bool
    var onInsert: (String) -> Void

    @State private var searchText: String = ""
    @State private var selectedIndex: Int = 0
    @State private var keyboardMonitor: Any?
    @State private var previousFirstResponder: NSResponder?
    @FocusState private var isSearchFieldFocused: Bool

    private var filteredSnippets: [SnippetStore.Snippet] {
        appViewModel.snippetStore.filter(query: searchText)
    }

    private var selectedSnippet: SnippetStore.Snippet? {
        guard filteredSnippets.indices.contains(selectedIndex) else { return nil }
        return filteredSnippets[selectedIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("テンプレートを検索...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFieldFocused)
                .padding(12)

            Divider()

            ScrollViewReader { proxy in
                List {
                    if filteredSnippets.isEmpty {
                        Text("一致するテンプレートがありません")
                            .foregroundStyle(Color.kobaMute)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(Array(filteredSnippets.enumerated()), id: \.element.id) { index, snippet in
                            Text(snippet.title)
                                .font(.system(size: 13, weight: index == selectedIndex ? .semibold : .regular))
                                .foregroundStyle(index == selectedIndex ? Color.white : Color.kobaInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .listRowSeparator(.hidden)
                                .listRowBackground(index == selectedIndex ? Color.kobaAccent : Color.clear)
                                .id(snippet.id)
                                .onTapGesture {
                                    selectedIndex = index
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: 220)
                .onChange(of: selectedIndex) { _, _ in
                    guard let id = selectedSnippet?.id else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onChange(of: filteredSnippets.count) { _, newCount in
                    guard newCount > 0 else {
                        selectedIndex = 0
                        return
                    }
                    selectedIndex = min(selectedIndex, newCount - 1)
                }
                .onChange(of: searchText) { _, _ in
                    selectedIndex = 0
                    guard let firstID = filteredSnippets.first?.id else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(firstID, anchor: .top)
                    }
                }
            }

            Divider()

            Text("Enter: 挿入  ↑↓: 選択  Esc: 閉じる")
                .font(.caption)
                .foregroundStyle(Color.kobaMute)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(width: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.kobaLine.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .onAppear {
            previousFirstResponder = NSApp.keyWindow?.firstResponder
            isSearchFieldFocused = true
            installKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onExitCommand {
            close()
        }
    }

    private func moveSelection(by offset: Int) {
        guard !filteredSnippets.isEmpty else { return }
        selectedIndex = max(0, min(selectedIndex + offset, filteredSnippets.count - 1))
    }

    private func insertSelectedSnippet() {
        guard let snippet = selectedSnippet else { return }
        onInsert(snippet.prompt)
        close()
    }

    private func close() {
        isVisible = false
        if let previousFirstResponder {
            NSApp.keyWindow?.makeFirstResponder(previousFirstResponder)
        }
    }

    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isVisible else { return event }

            switch event.keyCode {
            case 125: // ↓
                moveSelection(by: 1)
                return nil
            case 126: // ↑
                moveSelection(by: -1)
                return nil
            case 36, 76: // Return / Enter
                insertSelectedSnippet()
                return nil
            case 53: // Esc
                close()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        guard let keyboardMonitor else { return }
        NSEvent.removeMonitor(keyboardMonitor)
        self.keyboardMonitor = nil
    }
}
