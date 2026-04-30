import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

struct DiffSheetView: View {
    let preloadText: String
    let preloadFileName: String
    var isInline: Bool = false

    @State private var vm = DiffViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var isTargetedA = false
    @State private var isTargetedB = false

    var body: some View {
        VStack(spacing: 0) {
            // Header（シートモードのみ表示）
            if !isInline {
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
            }

            // 上段: 左右テキスト入力
            HStack(spacing: 0) {
                // MARK: A エリア
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(vm.fileNameA.isEmpty ? "A" : vm.fileNameA)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.kobaMute)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if !vm.textA.isEmpty {
                            Button {
                                vm.textA = ""; vm.fileNameA = ""; vm.scheduleUpdate()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.kobaMute)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                        }
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
                .onDrop(of: [.fileURL], isTargeted: $isTargetedA) { providers in
                    loadDrop(providers: providers, target: .a)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [6])
                        )
                        .foregroundStyle(isTargetedA ? Color.kobaAccent : Color.clear)
                        .background(isTargetedA ? Color.kobaAccent.opacity(0.06) : Color.clear)
                        .padding(4)
                        .allowsHitTesting(false)
                )

                Rectangle().fill(Color.kobaLine).frame(width: 1)

                // MARK: B エリア
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(vm.fileNameB.isEmpty ? "B" : vm.fileNameB)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.kobaMute)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if !vm.textB.isEmpty {
                            Button {
                                vm.textB = ""; vm.fileNameB = ""; vm.scheduleUpdate()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.kobaMute)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                        }
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
                .onDrop(of: [.fileURL], isTargeted: $isTargetedB) { providers in
                    loadDrop(providers: providers, target: .b)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [6])
                        )
                        .foregroundStyle(isTargetedB ? Color.kobaAccent : Color.clear)
                        .background(isTargetedB ? Color.kobaAccent.opacity(0.06) : Color.clear)
                        .padding(4)
                )
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 220)

            Rectangle().fill(Color.kobaLine).frame(height: 1)

            // Mode toggle: Raw / Rendered
            HStack {
                Spacer()
                Picker("", selection: Binding(
                    get: { vm.isRenderedMode },
                    set: { newValue in
                        if newValue != vm.isRenderedMode {
                            vm.toggleRenderedMode()
                        }
                    }
                )) {
                    Text("Raw").tag(false)
                    Text("Rendered").tag(true)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 200)
                Spacer()
            }
            .padding(.vertical, 6)
            .background(Color.kobaSurface)
            .overlay(Rectangle().fill(Color.kobaLine).frame(height: 1), alignment: .bottom)

            // 下段: Diff結果
            if vm.isRenderedMode {
                // Rendered モード: 左右サイドバイサイド WebView
                HStack(spacing: 0) {
                    RenderedDiffWebView(html: vm.renderedHTMLForA)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Rectangle().fill(Color.kobaLine).frame(width: 1)

                    RenderedDiffWebView(html: vm.renderedHTMLForB)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.kobaPaper)
            } else {
                // Raw モード: 既存の差分行表示
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
        }
        .frame(minWidth: 700, minHeight: 520)
        .background(Color.kobaPaper)
        .onAppear {
            if !preloadText.isEmpty {
                vm.textA = preloadText
                vm.fileNameA = preloadFileName
                vm.scheduleUpdate()
            }
        }
    }

    enum FileTarget {
        case a
        case b
    }

    @discardableResult
    private func loadDrop(providers: [NSItemProvider], target: FileTarget) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                if target == .a {
                    vm.textA = content
                    vm.fileNameA = url.lastPathComponent
                } else {
                    vm.textB = content
                    vm.fileNameB = url.lastPathComponent
                }
                vm.scheduleUpdate()
            }
        }
        return true
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
                vm.fileNameA = url.lastPathComponent
            } else {
                vm.textB = content
                vm.fileNameB = url.lastPathComponent
            }
            vm.scheduleUpdate()
        }
    }
}

// MARK: - Inline (tab-embedded) version — no sheet chrome

struct DiffInlineView: View {
    let preloadText: String
    let preloadFileName: String

    var body: some View {
        DiffSheetView(preloadText: preloadText, preloadFileName: preloadFileName, isInline: true)
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

// MARK: - Rendered diff WebView (lightweight WKWebView wrapper)

private struct RenderedDiffWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        let coord = context.coordinator
        if coord.lastHTML != html && !html.isEmpty {
            coord.lastHTML = html
            wv.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var lastHTML: String = ""
    }
}
