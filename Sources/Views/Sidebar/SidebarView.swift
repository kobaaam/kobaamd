import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var fileTreeViewModel = FileTreeViewModel()
    @State private var selectedTab: SidebarTab = .files

    enum SidebarTab: String, CaseIterable {
        case files = "Files"
        case search = "Search"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selectedTab == tab ? Color.kobaInk : Color.kobaMute)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .background(
                        selectedTab == tab
                            ? Color.kobaSurface
                            : Color.kobaSidebar
                    )
                    .overlay(
                        selectedTab == tab
                            ? Rectangle().fill(Color.kobaAccent).frame(height: 2)
                            : Rectangle().fill(Color.clear).frame(height: 2),
                        alignment: .bottom
                    )
                }
            }
            .frame(height: 32)
            .background(Color.kobaSidebar)
            .overlay(Rectangle().fill(Color.kobaLine).frame(height: 1), alignment: .bottom)

            switch selectedTab {
            case .files:
                filePanel
            case .search:
                SearchView(fileTreeViewModel: fileTreeViewModel)
            }
        }
        .background(Color.kobaSidebar)
        .onReceive(NotificationCenter.default.publisher(for: .openFolderRequested)) { _ in
            fileTreeViewModel.openFolder()
        }
        .onAppear {
            fileTreeViewModel.restoreLastFolder()
            if let lastURL = AppState.loadLastFile(),
               FileManager.default.fileExists(atPath: lastURL.path) {
                appViewModel.selectedFileURL = lastURL
                Task {
                    if let content = try? FileService().readFile(at: lastURL) {
                        await MainActor.run {
                            appViewModel.editorText = content
                            appViewModel.markSaved()
                        }
                    }
                }
            }
        }
    }

    var filePanel: some View {
        VStack(spacing: 0) {
            if fileTreeViewModel.nodes.isEmpty {
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
                        fileTreeViewModel.openFolder()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Open Folder")
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
                // Section header
                HStack {
                    Text("FILES")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.kobaMute2)
                    Spacer()
                    Button {
                        fileTreeViewModel.openFolder()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.kobaMute)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                FileTreeView(fileTreeViewModel: fileTreeViewModel)
            }
        }
    }

    private func openRecent(_ url: URL) {
        let folder = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path) {
            fileTreeViewModel.openFolder(url: folder)
        }
        appViewModel.selectedFileURL = url
        Task {
            if let content = try? FileService().readFile(at: url) {
                await MainActor.run {
                    appViewModel.editorText = content
                    appViewModel.markSaved()
                }
            }
        }
    }
}
