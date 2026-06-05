import SwiftUI

// MARK: - E1 left rail: Sessions (top) + Files (bottom)

struct E1SessionRailView: View {
    private let sessionsFraction: CGFloat = 0.42

    var body: some View {
        GeometryReader { geo in
            let sessionsHeight = max(80, geo.size.height * sessionsFraction)
            VStack(spacing: 0) {
                e1RailSection(
                    title: "Sessions",
                    subtitle: "git worktree — KMD-221",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .frame(height: sessionsHeight)

                KobaHDivider()

                e1RailSection(
                    title: "Files",
                    subtitle: "scoped tree — KMD-223",
                    systemImage: "folder"
                )
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kobaSurface)
    }

    private func e1RailSection(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kobaInk)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.kobaMute)
                .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}