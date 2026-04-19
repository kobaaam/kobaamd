import SwiftUI

struct SidebarView: View {
    @State private var fileTreeViewModel = FileTreeViewModel()

    var body: some View {
        FileTreeView(fileTreeViewModel: fileTreeViewModel)
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
