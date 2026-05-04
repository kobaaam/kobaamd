import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var appViewModel

    private var fileTreeViewModel: FileTreeViewModel { appViewModel.fileTreeViewModel }
    @State private var reloadDebounceTask: Task<Void, Never>? = nil

    // MARK: - Split & collapse state

    @State private var outlinePanelRatio: CGFloat = 0.35
    @State private var dragStartRatio: CGFloat = 0.35
    @State private var isTodoExpanded: Bool = false
    @State private var isDraggingHandle: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Section header — EXPLORER
            sectionHeader("EXPLORER")

            // MARK: File tree + resize handle + outline (flex area)
            GeometryReader { geo in
                let todoHeaderHeight: CGFloat = 28
                let todoBodyHeight: CGFloat = isTodoExpanded ? min(240, geo.size.height * 0.35) : 0
                let availableHeight = geo.size.height - todoHeaderHeight - todoBodyHeight
                let isOutlineEmpty = appViewModel.outlineViewModel.items.isEmpty
                let outlineHeight: CGFloat = isOutlineEmpty ? 60 : max(60, availableHeight * outlinePanelRatio)
                let fileHeight = max(60, availableHeight - outlineHeight)

                VStack(spacing: 0) {
                    // ── File panel ──
                    filePanel
                        .frame(height: fileHeight)
                        .clipped()

                    // ── Resize handle ──
                    resizeHandle(availableHeight: availableHeight)

                    // ── Outline header + panel ──
                    sectionHeader("OUTLINE")

                    if isOutlineEmpty {
                        Text("見出しが見つかりません")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.kobaMute)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(height: outlineHeight - 28)
                    } else {
                        OutlineView(outlineViewModel: appViewModel.outlineViewModel)
                            .frame(height: outlineHeight - 28) // subtract outline header height
                            .clipped()
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("アウトライン")
                    }

                    // ── TODO collapsible area ──
                    todoSection
                        .frame(height: todoHeaderHeight + todoBodyHeight)
                        .clipped()
                }
            }
        }
        .background(Color.kobaSidebar)
        .onReceive(NotificationCenter.default.publisher(for: .openRecentNotification)) { notification in
            if let url = notification.object as? URL {
                openRecent(url)
            }
        }
        // Auto-refresh when app regains focus — debounced 1s to avoid rapid-fire reloads
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reloadDebounceTask?.cancel()
            reloadDebounceTask = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await MainActor.run { fileTreeViewModel.reload() }
            }
        }
        .onAppear {
            fileTreeViewModel.restoreWorkspace()

            // 前回開いていたファイルを復元（Finder 経由のオープンは MainWindowView.onChange が担当）
            if let lastURL = AppState.loadLastFile(),
               FileManager.default.fileExists(atPath: lastURL.path) {
                Task.detached {
                    if let content = try? FileService().readFile(at: lastURL) {
                        await MainActor.run {
                            appViewModel.openInTab(url: lastURL, content: content)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.kobaMute2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(height: 28)
    }

    // MARK: - Resize handle

    private func resizeHandle(availableHeight: CGFloat) -> some View {
        Color.kobaLine
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { value in
                        if !isDraggingHandle {
                            isDraggingHandle = true
                            dragStartRatio = outlinePanelRatio
                        }
                        let newRatio = dragStartRatio - value.translation.height / availableHeight
                        outlinePanelRatio = min(0.9, max(0.1, newRatio))
                    }
                    .onEnded { _ in
                        isDraggingHandle = false
                    }
            )
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() }
                else { NSCursor.pop() }
            }
            .accessibilityLabel("アウトラインパネルのサイズ調整")
    }

    // MARK: - TODO collapsible section

    private var todoSection: some View {
        let todoCount = appViewModel.todoViewModel.items.count
        let headerColor: Color = todoCount > 0 ? .kobaInk : .kobaMute2

        return VStack(spacing: 0) {
            // Separator
            Color.kobaLine
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isTodoExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isTodoExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("TODO")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    if todoCount > 0 {
                        Text("(\(todoCount))")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    Spacer()
                }
                .foregroundStyle(headerColor)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.kobaSurface)
            .accessibilityLabel("TODO一覧")
            .accessibilityHint("クリックで展開・折り畳み")

            // Body (expanded)
            if isTodoExpanded {
                TodoView(todoViewModel: appViewModel.todoViewModel)
                    .frame(maxHeight: 240)
            }
        }
    }

    // MARK: - File panel (preserved from original)

    var filePanel: some View {
        VStack(spacing: 0) {
            if fileTreeViewModel.folders.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.kobaInk.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 48, height: 48)
                        Text("md")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.kobaInk)
                    }
                    VStack(spacing: 6) {
                        Text("No folder open")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.kobaInk)
                        Text("Point kobaamd at a folder —\nit becomes your workspace.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.kobaMute)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        fileTreeViewModel.addFolder()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Add Folder")
                                .font(.system(size: 12, weight: .semibold))
                            Text("⌘O")
                                .font(.system(size: 11, design: .monospaced))
                                .opacity(0.7)
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.kobaInk)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)

                    // Recent files
                    let recents = AppState.loadRecentFiles()
                    if !recents.isEmpty {
                        VStack(spacing: 4) {
                            Text("RECENT")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.kobaMute2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(recents.prefix(5), id: \.self) { url in
                                Button {
                                    openRecent(url)
                                } label: {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Color.kobaMute)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FileTreeView(fileTreeViewModel: fileTreeViewModel)
            }
        }
    }

    // MARK: - Open recent (preserved from original)

    private func openRecent(_ url: URL) {
        let folder = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path) {
            fileTreeViewModel.openFolder(url: folder)
        }
        appViewModel.selectedFileURL = url
        Task.detached {
            if let content = try? FileService().readFile(at: url) {
                await MainActor.run {
                    appViewModel.editorText = content
                    appViewModel.markSaved()
                }
            }
        }
    }
}
