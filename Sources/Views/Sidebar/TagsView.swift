import SwiftUI

struct TagsView: View {
    @Environment(AppViewModel.self) private var appViewModel
    let tagsViewModel: TagsViewModel
    @State private var hoveredTagID: String? = nil
    @State private var hoveredFileID: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            sortPicker
            content
        }
        .background(Color.kobaSidebar)
    }

    private var sortPicker: some View {
        Picker("Sort", selection: Binding(
            get: { tagsViewModel.sortMode },
            set: { tagsViewModel.sortMode = $0 }
        )) {
            ForEach(TagSortMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .accessibilityLabel("タグの並び替え")
    }

    @ViewBuilder
    private var content: some View {
        if tagsViewModel.isScanning && tagsViewModel.tags.isEmpty {
            VStack {
                Spacer()
                ProgressView().controlSize(.small)
                Text("スキャン中…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
                    .padding(.top, 6)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tagsViewModel.tags.isEmpty {
            VStack {
                Spacer()
                Text("タグが見つかりません")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.kobaMute)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(tagsViewModel.tags) { tag in
                        tagRow(tag)
                        if tagsViewModel.selectedTag == tag.name {
                            ForEach(tagsViewModel.taggedFiles) { file in
                                fileRow(file)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func tagRow(_ tag: TagItem) -> some View {
        let isSelected = tagsViewModel.selectedTag == tag.name
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.kobaMute)
                .frame(width: 12)

            Text("#" + tag.name)
                .font(.system(size: 12))
                .foregroundStyle(Color.kobaInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(tag.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.kobaMute)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background(
            isSelected
                ? Color.kobaInk.opacity(0.08)
                : (hoveredTagID == tag.id ? Color.kobaInk.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredTagID = hovering ? tag.id : (hoveredTagID == tag.id ? nil : hoveredTagID)
        }
        .onTapGesture {
            tagsViewModel.selectTag(tag.name)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("タグ \(tag.name) \(tag.count)件")
        .accessibilityHint("クリックで該当記事を表示")
    }

    @ViewBuilder
    private func fileRow(_ file: TaggedFile) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(Color.kobaMute)

            Text(file.fileName)
                .font(.system(size: 11))
                .foregroundStyle(Color.kobaInk)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 30)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(
            hoveredFileID == file.id
                ? Color.kobaInk.opacity(0.06)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredFileID = hovering ? file.id : (hoveredFileID == file.id ? nil : hoveredFileID)
        }
        .onTapGesture {
            Task { @MainActor in
                await appViewModel.openFile(url: file.url)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(file.fileName) を開く")
    }
}
