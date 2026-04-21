import SwiftUI

// MARK: - Main window

struct MainWindowView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var splitFraction: CGFloat = 0.55

    private var isMDFile: Bool {
        let ext = appViewModel.selectedFileURL?.pathExtension.lowercased() ?? ""
        return ext == "md" || ext == "markdown" || ext.isEmpty
    }

    var body: some View {
        @Bindable var vm = appViewModel
        VStack(spacing: 0) {
            // ── Main pane ──────────────────────────────────────────
            HStack(spacing: 0) {
                if appViewModel.isSidebarVisible {
                    SidebarView()
                        .frame(width: 240)
                        .transition(.move(edge: .leading))

                    KobaDivider()
                }

                VStack(spacing: 0) {
                    TabBarView()

                    if appViewModel.previewMode == .wysiwyg {
                        @Bindable var vm = appViewModel
                        WYSIWYGEditorView(text: $vm.editorText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.kobaPaper)
                    } else if appViewModel.previewMode == .split {
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                EditorView()
                                    .frame(width: max(280, geo.size.width * splitFraction))
                                    .background(Color.kobaPaper)
                                SplitDivider(fraction: $splitFraction, availableWidth: geo.size.width)
                                PreviewView()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.kobaSurface)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EditorView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.kobaPaper)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Git panel (trailing, slides in from right)
                if appViewModel.isGitPanelVisible {
                    KobaDivider()
                    GitPanel(gitVM: appViewModel.gitViewModel)
                        .frame(width: 300)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: appViewModel.isSidebarVisible)
            .animation(.easeInOut(duration: 0.2), value: appViewModel.isGitPanelVisible)

            // ── Status / command bar ───────────────────────────────
            StatusCommandBar(previewMode: $vm.previewMode, isMDFile: isMDFile)
        }
        .navigationTitle(appViewModel.selectedFileURL?.lastPathComponent ?? "kobaamd")
        .background(Color.kobaPaper)
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .onChange(of: appViewModel.selectedFileURL) { _, url in
            let ext = url?.pathExtension.lowercased() ?? ""
            let isMD = ext == "md" || ext == "markdown" || ext.isEmpty
            if !isMD && appViewModel.previewMode == .wysiwyg {
                appViewModel.previewMode = .split
            }
        }
        .onChange(of: AppState.shared.pendingOpenFileURL) { _, fileURL in
            guard let url = fileURL else { return }
            AppState.shared.pendingOpenFileURL = nil
            Task.detached(priority: .userInitiated) {
                if let content = try? FileService().readFile(at: url) {
                    await MainActor.run {
                        appViewModel.openInTab(url: url, content: content)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTabRequested)) { _ in
            appViewModel.newTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sidebarToggleRequested)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                appViewModel.isSidebarVisible.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitPanelRequested)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                appViewModel.isGitPanelVisible.toggle()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("サイドバーの表示/非表示 (⌘B)")

                Button {
                    NotificationCenter.default.post(name: .openFolderRequested, object: nil)
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open Folder (⌘O)")
            }

            // Center: preview mode selector (only when a file is open)
            ToolbarItem(placement: .principal) {
                if vm.selectedFileURL != nil {
                    Picker("", selection: $vm.previewMode) {
                        Image(systemName: "pencil").tag(PreviewMode.off)
                        Image(systemName: "rectangle.split.2x1").tag(PreviewMode.split)
                        if isMDFile {
                            Image(systemName: "eye").tag(PreviewMode.wysiwyg)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .labelsHidden()
                    .help("プレビューモード切り替え")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .newFileRequested, object: nil)
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .help("New File (⌘N)")

                // Save button doubles as autosave indicator
                Button {
                    NotificationCenter.default.post(name: .saveRequested, object: nil)
                } label: {
                    Image(systemName: vm.isDirty ? "circle.fill" : "checkmark.circle")
                        .foregroundStyle(vm.isDirty ? Color.kobaAccent : .secondary)
                }
                .help("Save (⌘S)")

                Divider()

                Button {
                    NotificationCenter.default.post(name: .findRequested, object: nil)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Find & Replace (⌘F)")

                Button {
                    NotificationCenter.default.post(name: .aiAssistRequested, object: nil)
                } label: {
                    Image(systemName: "sparkles")
                }
                .help("AI アシスト (⌘E)")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.isGitPanelVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sourcecontrol.changes")
                        .symbolVariant(vm.isGitPanelVisible ? .fill : .none)
                }
                .help("Git パネル (⌘G)")
            }
        }
    }
}

// MARK: - Status / command bar

struct StatusCommandBar: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Binding var previewMode: PreviewMode
    var isMDFile: Bool = true

    var filePath: String {
        guard let url = appViewModel.selectedFileURL else { return "" }
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? url.lastPathComponent : "\(parent) / \(url.lastPathComponent)"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left — breadcrumb + line count
            HStack(spacing: 8) {
                if !filePath.isEmpty {
                    Text(filePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.kobaMute)
                    if appViewModel.isDirty {
                        Circle()
                            .fill(Color.kobaAccent)
                            .frame(width: 5, height: 5)
                    }
                    kobaLineSep()
                }
                if appViewModel.lineCount > 0 {
                    Text("\(appViewModel.lineCount) lines")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.kobaMute2)
                    kobaLineSep()
                    Text("\(appViewModel.wordCount) words")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.kobaMute2)
                }
            }
            .padding(.leading, 14)

            Spacer()

            // Right — git branch + version + preview toggle + keyboard hints
            HStack(spacing: 14) {
                if appViewModel.gitViewModel.isGitRepo && !appViewModel.gitViewModel.branch.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(appViewModel.gitViewModel.branch)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundStyle(Color.kobaMute)
                    kobaLineSep()
                }

                Text(AppVersion.display)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.kobaMute2)

                kobaLineSep()
                // Preview toggle
                HStack(spacing: 0) {
                    ForEach(PreviewMode.allCases.filter { isMDFile || $0 != .wysiwyg }, id: \.self) { mode in
                        Button {
                            previewMode = mode
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(previewMode == mode ? Color.white : Color.kobaMute)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(previewMode == mode ? Color.kobaInk : Color.clear)
                        }
                        .buttonStyle(.plain)
                        .help(helpText(for: mode))
                    }
                }
                .background(Color.kobaLine.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.kobaLine, lineWidth: 1)
                )

                kobaLineSep()

                KbdHint(key: "⌘F", label: "Find")
                KbdHint(key: "⌘S", label: "Save")
            }
            .padding(.trailing, 14)
        }
        .frame(height: 30)
        .background(Color.kobaSurface)
        .overlay(KobaDivider(), alignment: .top)
    }

    func kobaLineSep() -> some View {
        Rectangle()
            .fill(Color.kobaLine)
            .frame(width: 1, height: 12)
    }

    func helpText(for mode: PreviewMode) -> String {
        switch mode {
        case .off:     return "エディタのみ表示"
        case .split:   return "エディタ + プレビューを並べて表示"
        case .wysiwyg: return "リアルタイムプレビュー（WYSIWYG）"
        }
    }
}

// MARK: - Small shared components

struct KobaDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.kobaLine)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}

// MARK: - Draggable split divider

struct SplitDivider: View {
    @Binding var fraction: CGFloat
    let availableWidth: CGFloat
    @State private var baseF: CGFloat = 0
    @State private var isDragging: Bool = false

    var body: some View {
        Color.kobaLine
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        if !isDragging {
                            isDragging = true
                            baseF = fraction
                        }
                        let newF = baseF + v.translation.width / availableWidth
                        fraction = min(0.8, max(0.2, newF))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
    }
}

struct KbdHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.kobaMute)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.kobaSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.kobaLine, lineWidth: 1)
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.kobaMute2)
        }
    }
}
