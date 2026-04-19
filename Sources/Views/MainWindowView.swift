import SwiftUI

// MARK: - Design tokens (Linear/Raycast vibe)
extension Color {
    static let kobaPaper    = Color(hex: "fdfcf8")
    static let kobaSurface  = Color(hex: "ffffff")
    static let kobaSidebar  = Color(hex: "fafaf7")
    static let kobaAccent   = Color(hex: "FF5B1F")
    static let kobaLine     = Color(hex: "e0ddd8")
    static let kobaMute     = Color(hex: "888888")
    static let kobaMute2    = Color(hex: "aaaaaa")
    static let kobaInk      = Color(hex: "1a1a1a")

    init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8)  & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }
}

// MARK: - Main window

struct MainWindowView: View {
    @Environment(AppViewModel.self) private var appViewModel

    var body: some View {
        @Bindable var vm = appViewModel
        VStack(spacing: 0) {
            // ── Main pane ──────────────────────────────────────────
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 240)

                KobaDivider()

                EditorView()
                    .frame(minWidth: 320, maxWidth: .infinity)
                    .background(Color.kobaPaper)

                if appViewModel.previewMode == .split {
                    KobaDivider()
                    PreviewView()
                        .frame(minWidth: 260, idealWidth: 380)
                        .background(Color.kobaSurface)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Status / command bar ───────────────────────────────
            StatusCommandBar(previewMode: $vm.previewMode)
        }
        .background(Color.kobaPaper)
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    NotificationCenter.default.post(name: .openFolderRequested, object: nil)
                } label: {
                    Image(systemName: "folder")
                }
                .help("Open Folder (⌘O)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(name: .newFileRequested, object: nil)
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .help("New File (⌘N)")

                Button {
                    NotificationCenter.default.post(name: .saveRequested, object: nil)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save (⌘S)")

                Divider()

                Button {
                    NotificationCenter.default.post(name: .findRequested, object: nil)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Find & Replace (⌘F)")
            }
        }
    }
}

// MARK: - Status / command bar

struct StatusCommandBar: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Binding var previewMode: PreviewMode

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
                }
            }
            .padding(.leading, 14)

            Spacer()

            // Right — version + preview toggle + keyboard hints
            HStack(spacing: 14) {
                Text(AppVersion.display)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.kobaMute2)

                kobaLineSep()
                // Preview toggle
                HStack(spacing: 0) {
                    ForEach(PreviewMode.allCases, id: \.self) { mode in
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
