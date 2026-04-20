import SwiftUI

// MARK: - Git Panel (⌘G)
//
// Shows: branch name, changed files list, unified diff viewer, staging controls,
// commit message input, recent commit log.

struct GitPanel: View {
    @Bindable var gitVM: GitViewModel
    @State private var selectedTab: GitTab = .changes

    enum GitTab: String, CaseIterable {
        case changes = "変更"
        case log     = "履歴"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ─────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(Color.kobaAccent)
                Text(gitVM.branch.isEmpty ? "—" : gitVM.branch)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.kobaInk)
                Spacer()
                Button {
                    gitVM.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.kobaMute)
                .help("更新 (⌘G)")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.kobaSurface)
            .overlay(Rectangle().fill(Color.kobaLine).frame(height: 1), alignment: .bottom)

            // ── Tab picker ─────────────────────────────────────────
            HStack(spacing: 0) {
                ForEach(GitTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selectedTab == tab ? Color.kobaInk : Color.kobaMute)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(selectedTab == tab ? Color.kobaLine.opacity(0.5) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.kobaSurface)
            .overlay(Rectangle().fill(Color.kobaLine).frame(height: 1), alignment: .bottom)

            // ── Content ────────────────────────────────────────────
            if gitVM.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedTab == .changes {
                ChangesTabView(gitVM: gitVM)
            } else {
                LogTabView(commits: gitVM.recentCommits)
            }
        }
        .alert("エラー", isPresented: $gitVM.showError) {
            Button("OK") {}
        } message: {
            Text(gitVM.errorMessage ?? "")
        }
        .background(Color.kobaSidebar)
    }
}

// MARK: - Changes Tab

private struct ChangesTabView: View {
    @Bindable var gitVM: GitViewModel

    private var staged:   [GitFileStatus] { gitVM.changedFiles.filter(\.isStaged) }
    private var unstaged: [GitFileStatus] { gitVM.changedFiles.filter { !$0.isStaged } }

    var body: some View {
        VStack(spacing: 0) {
            // File list
            List(selection: Binding(
                get: { gitVM.selectedFile?.id },
                set: { id in
                    if let f = gitVM.changedFiles.first(where: { $0.id == id }) {
                        gitVM.selectFile(f)
                    }
                }
            )) {
                if !staged.isEmpty {
                    Section {
                        ForEach(staged) { file in
                            FileStatusRow(file: file) {
                                gitVM.unstage(file)
                            }
                        }
                    } header: {
                        HStack {
                            Text("ステージ済")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.kobaMute)
                            Spacer()
                        }
                    }
                }

                if !unstaged.isEmpty {
                    Section {
                        ForEach(unstaged) { file in
                            FileStatusRow(file: file) {
                                gitVM.stage(file)
                            }
                        }
                    } header: {
                        HStack {
                            Text("変更")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.kobaMute)
                            Spacer()
                            Button("全てステージ") { gitVM.stageAll() }
                                .font(.system(size: 10))
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.kobaAccent)
                        }
                    }
                }

                if gitVM.changedFiles.isEmpty {
                    Text("変更なし")
                        .foregroundStyle(Color.kobaMute)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .frame(minHeight: 120, maxHeight: 260)

            // Diff viewer
            if !gitVM.diffContent.isEmpty {
                Rectangle().fill(Color.kobaLine).frame(height: 1)
                DiffView(content: gitVM.diffContent)
                    .frame(minHeight: 100, maxHeight: .infinity)
            }

            Rectangle().fill(Color.kobaLine).frame(height: 1)

            // Commit area
            VStack(spacing: 8) {
                TextEditor(text: $gitVM.commitMessage)
                    .font(.system(size: 12))
                    .frame(height: 70)
                    .scrollContentBackground(.hidden)
                    .background(Color.kobaSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.kobaLine, lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if gitVM.commitMessage.isEmpty {
                            Text("コミットメッセージを入力...")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.kobaMute2)
                                .padding(.horizontal, 5)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }

                Button {
                    gitVM.commit()
                } label: {
                    Text("コミット")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(staged.isEmpty || gitVM.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.kobaMute.opacity(0.3)
                                    : Color.kobaAccent)
                        .foregroundStyle(staged.isEmpty || gitVM.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                         ? Color.kobaMute : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(staged.isEmpty || gitVM.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
            .background(Color.kobaSurface)
        }
    }
}

// MARK: - File Status Row

private struct FileStatusRow: View {
    let file: GitFileStatus
    let onToggle: () -> Void

    private var stateColor: Color {
        switch file.state {
        case .added:     return .green
        case .deleted:   return .red
        case .modified, .staged: return Color.kobaAccent
        case .untracked: return Color.kobaMute
        case .renamed:   return .purple
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(file.state.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(stateColor)
                .frame(width: 14)

            Text(URL(fileURLWithPath: file.path).lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(Color.kobaInk)
                .lineLimit(1)

            Spacer()

            Button {
                onToggle()
            } label: {
                Image(systemName: file.isStaged ? "minus.circle" : "plus.circle")
                    .foregroundStyle(file.isStaged ? Color.kobaMute : Color.kobaAccent)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help(file.isStaged ? "ステージ解除" : "ステージ")
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Diff View (unified diff with syntax coloring)

struct DiffView: View {
    let content: String

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    diffLine(line)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.kobaPaper)
    }

    private var lines: [String] {
        content.components(separatedBy: "\n")
    }

    @ViewBuilder
    private func diffLine(_ line: String) -> some View {
        let (text, bg, fg) = attributes(for: line)
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg)
    }

    private func attributes(for line: String) -> (String, Color, Color) {
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return (line, Color.clear, Color.kobaMute)
        }
        if line.hasPrefix("+") {
            return (line, Color.green.opacity(0.08), Color(NSColor(srgbRed: 0.10, green: 0.45, blue: 0.20, alpha: 1)))
        }
        if line.hasPrefix("-") {
            return (line, Color.red.opacity(0.08), Color(NSColor(srgbRed: 0.70, green: 0.15, blue: 0.15, alpha: 1)))
        }
        if line.hasPrefix("@@") {
            return (line, Color.blue.opacity(0.06), Color.blue.opacity(0.7))
        }
        if line.hasPrefix("diff ") || line.hasPrefix("index ") {
            return (line, Color.clear, Color.kobaMute)
        }
        return (line, Color.clear, Color.kobaInk)
    }
}

// MARK: - Log Tab

private struct LogTabView: View {
    let commits: [GitCommit]

    var body: some View {
        if commits.isEmpty {
            Text("コミット履歴なし")
                .foregroundStyle(Color.kobaMute)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(commits) { commit in
                VStack(alignment: .leading, spacing: 3) {
                    Text(commit.subject)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kobaInk)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(commit.shortHash)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.kobaAccent)
                        Text(commit.author)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kobaMute)
                        Text(commit.date)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kobaMute2)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
        }
    }
}
