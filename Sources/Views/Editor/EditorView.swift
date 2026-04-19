import SwiftUI

struct EditorView: View {
    @Environment(AppViewModel.self) private var appViewModel

    var body: some View {
        @Bindable var vm = appViewModel
        NSTextViewWrapper(binding: $vm.editorText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
