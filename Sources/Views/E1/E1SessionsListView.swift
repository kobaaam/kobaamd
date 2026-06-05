import SwiftUI

// MARK: - Session list (KMD-222)

struct E1SessionsListView: View {
    @Bindable var coordinator: SessionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
                Text("Sessions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kobaInk)
                Spacer()
                if coordinator.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if let error = coordinator.loadError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            if coordinator.sessions.isEmpty && !coordinator.isLoading {
                VStack(alignment: .leading, spacing: 2) {
                    E1SessionRow(
                        session: WorktreeSession.localShell(),
                        isSelected: coordinator.activeSessionID == nil
                    ) {
                        coordinator.activateLocalShell()
                    }
                    e1EmptySessions
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(coordinator.sessions) { session in
                            E1SessionRow(
                                session: session,
                                isSelected: coordinator.activeSessionID == session.id
                            ) {
                                coordinator.selectSession(id: session.id)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var e1EmptySessions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("git worktree は未登録")
                .font(.system(size: 11))
                .foregroundStyle(Color.kobaMute)
            Text("ツールバーのフォルダでリポジトリを開くと worktree 一覧が表示されます。")
                .font(.system(size: 10))
                .foregroundStyle(Color.kobaMute2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("worktree がありません。フォルダボタンで git リポジトリを開いてください。")
    }
}

private struct E1SessionRow: View {
    let session: WorktreeSession
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isSelected ? Color.kobaAccent : Color.kobaMute2)
                        .frame(width: 7, height: 7)
                    Text(session.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Color.kobaInk)
                        .lineLimit(1)
                    if session.isMainWorktree {
                        Text("main")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.kobaMute)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.kobaSurface)
                            .clipShape(Capsule())
                    }
                }
                if let branch = session.branchName {
                    Text(branch)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.kobaMute)
                        .lineLimit(1)
                } else {
                    Text("detached")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.kobaMute2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.kobaAccentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilitySummary: String {
        var parts = [session.name]
        if session.isMainWorktree { parts.append("main worktree") }
        if let branch = session.branchName {
            parts.append("branch \(branch)")
        } else {
            parts.append("detached")
        }
        return parts.joined(separator: ", ")
    }
}