import SwiftUI
import AppKit

struct DiffSheetView: View {
    @State private var vm = DiffViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Diff")
                    .font(.headline)
                Spacer()
                Button("閉じる") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.kobaMute)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Color.kobaSurface)
            .overlay(Rectangle().fill(Color.kobaLine).frame(height: 1), alignment: .bottom)

            // 上段: 左右テキスト入力
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("A")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.kobaMute)
                        Spacer()
                        Button("ファイル…") { pickFile(target: .a) }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.kobaAccent)
                    }
                    .padding(.horizontal, 8)

                    DiffTextEditor(
                        text: Binding(
                            get: { vm.textA },
                            set: {
                                vm.textA = $0
                                vm.scheduleUpdate()
                            }
                        )
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle().fill(Color.kobaLine).frame(width: 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("B")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.kobaMute)
                        Spacer()
                        Button("ファイル…") { pickFile(target: .b) }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.kobaAccent)
                    }
                    .padding(.horizontal, 8)

                    DiffTextEditor(
                        text: Binding(
                            get: { vm.textB },
                            set: {
                                vm.textB = $0
                                vm.scheduleUpdate()
                            }
                        )
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 220)

            Rectangle().fill(Color.kobaLine).frame(height: 1)

            // 下段: Diff結果
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if vm.lines.isEmpty && (!vm.textA.isEmpty || !vm.textB.isEmpty) {
                        Text("差分なし")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.kobaMute)
                            .padding(16)
                    } else {
                        ForEach(vm.lines) { line in
                            DiffLineView(line: line)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.kobaPaper)
        }
        .frame(minWidth: 700, minHeight: 520)
        .background(Color.kobaPaper)
    }

    enum FileTarget {
        case a
        case b
    }

    private func pickFile(target: FileTarget) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK,
           let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            if target == .a {
                vm.textA = content
            } else {
                vm.textB = content
            }
            vm.scheduleUpdate()
        }
    }
}

// MARK: - Inline text editor (NSTextView wrap)

private struct DiffTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let tv = NSTextView()

        tv.isEditable = true
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.backgroundColor = NSColor(Color.kobaPaper)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.delegate = context.coordinator

        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
        }
    }
}

// MARK: - Diff line row

private struct DiffLineView: View {
    let line: DiffViewModel.DiffLine

    var body: some View {
        Text(line.text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .background(background)
    }

    private var background: Color {
        switch line.kind {
        case .added:   return Color.green.opacity(0.15)
        case .removed: return Color.red.opacity(0.15)
        case .header:  return Color.gray.opacity(0.1)
        case .context: return Color.clear
        }
    }

    private var foreground: Color {
        switch line.kind {
        case .added:   return Color(NSColor.systemGreen)
        case .removed: return Color(NSColor.systemRed)
        case .header:  return Color.kobaMute
        case .context: return Color.kobaInk
        }
    }
}
