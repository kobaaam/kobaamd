import SwiftUI

// MARK: - Session list

struct E1SessionsListView: View {
    @Bindable var coordinator: SessionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
                Text("Sessions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kobaInk)
                Spacer()
                Button {
                    coordinator.addLocalSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.kobaMute)
                }
                .buttonStyle(.plain)
                .help("セッションを追加")
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(coordinator.sessions) { session in
                        E1SessionRow(
                            session: session,
                            isSelected: coordinator.activeSessionID == session.id,
                            canRemove: coordinator.canRemoveSessions
                        ) {
                            coordinator.selectSession(id: session.id)
                        } onDuplicate: {
                            coordinator.duplicateSession(id: session.id)
                        } onRemove: {
                            coordinator.removeLocalSession(id: session.id)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct E1SessionRow: View {
    let session: WorktreeSession
    let isSelected: Bool
    let canRemove: Bool
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onRemove: () -> Void

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
                    if session.isMainWorktree, !session.isLocalSession {
                        Text("main")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.kobaMute)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.kobaSurface)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.kobaMute)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.kobaAccentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onDuplicate()
            } label: {
                Label("同じフォルダで複製", systemImage: "plus.square.on.square")
            }
            Divider()
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("セッションを削除", systemImage: "trash")
            }
            .disabled(!canRemove)
        }
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("e1.session.\(session.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtitle: String {
        if session.isLocalSession {
            return session.displayPath
        }
        if let branch = session.branchName {
            return branch
        }
        return "detached"
    }

    private var accessibilitySummary: String {
        var parts = [session.name, subtitle]
        if session.isMainWorktree { parts.append("main worktree") }
        return parts.joined(separator: ", ")
    }
}