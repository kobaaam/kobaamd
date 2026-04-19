import SwiftUI

struct SidebarView: View {
    @State private var fileTreeViewModel = FileTreeViewModel()
    @State private var selectedTab: SidebarTab = .files

    enum SidebarTab: String, CaseIterable {
        case files = "Files"
        case search = "Search"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selectedTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch selectedTab {
            case .files:
                FileTreeView(fileTreeViewModel: fileTreeViewModel)
            case .search:
                SearchView(fileTreeViewModel: fileTreeViewModel)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    fileTreeViewModel.openFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                }
            }
        }
    }
}
