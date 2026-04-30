import SwiftUI

enum HelpSection: String, CaseIterable, Identifiable {
    case gettingStarted = "はじめに"
    case shortcuts = "ショートカット"
    case features = "機能ガイド"
    case ai = "AI 機能"
    case integrations = "連携"
    case faq = "FAQ"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .gettingStarted: return "book"
        case .shortcuts: return "keyboard"
        case .features: return "square.grid.2x2"
        case .ai: return "sparkles"
        case .integrations: return "link"
        case .faq: return "questionmark.circle"
        }
    }
}

struct HelpWindowView: View {
    @State private var selectedSection: HelpSection? = .gettingStarted

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(HelpSection.allCases, selection: $selectedSection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .frame(minWidth: 160)

                Rectangle()
                    .fill(Color.kobaLine)
                    .frame(height: 1)

                Text(AppVersion.display)
                    .font(.caption)
                    .foregroundStyle(Color.kobaMute)
                    .padding(.vertical, 8)
            }
            .background(Color.kobaSurface)
        } detail: {
            ScrollView {
                HelpContentView(section: selectedSection ?? .gettingStarted)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.kobaPaper)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 640, minHeight: 480)
    }
}
