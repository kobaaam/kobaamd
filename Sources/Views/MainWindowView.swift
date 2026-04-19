import SwiftUI

struct MainWindowView: View {
    @Bindable var appViewModel: AppViewModel

    init(appViewModel: AppViewModel) {
        self._appViewModel = .init(appViewModel)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            EditorView()
        } detail: {
            PreviewView()
        }
    }
}
