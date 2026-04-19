import SwiftUI

struct MainWindowView: View {
    @Environment(AppViewModel.self) private var appViewModel

    var windowTitle: String {
        let name = appViewModel.selectedFileURL?.lastPathComponent ?? "kobaamd"
        return appViewModel.isDirty ? "● \(name)" : name
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 200, idealWidth: 220)
        } content: {
            EditorView()
                .frame(minWidth: 350)
        } detail: {
            PreviewView()
                .frame(minWidth: 300)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(windowTitle)
                    .font(.headline)
            }
        }
    }
}
