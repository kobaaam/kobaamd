import SwiftUI

struct SearchView: View {
    @Environment(AppViewModel.self) private var appViewModel
    var fileTreeViewModel: FileTreeViewModel
    @State private var searchViewModel = SearchViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Search...", text: $searchViewModel.query)
                    .textFieldStyle(.roundedBorder)
                Button("Search") {
                    searchViewModel.search(in: fileTreeViewModel.rootURL)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(8)

            if searchViewModel.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }

            List(searchViewModel.results) { result in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(result.fileName).bold()
                        Text("L\(result.lineNumber)").foregroundStyle(.secondary)
                    }
                    Text(result.matchLine)
                        .font(.caption)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    appViewModel.selectedFileURL = result.fileURL
                    if let text = try? FileService().readFile(at: result.fileURL) {
                        appViewModel.editorText = text
                    }
                }
            }
            .listStyle(.plain)
        }
        .onChange(of: searchViewModel.query) { _, newValue in
            if newValue.isEmpty { searchViewModel.results = [] }
        }
    }
}
