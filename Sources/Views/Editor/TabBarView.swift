import SwiftUI

// MARK: - Tab bar

struct TabBarView: View {
    @Environment(AppViewModel.self) private var appViewModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(appViewModel.tabs) { tab in
                        TabItemView(tab: tab)
                    }
                }
            }

            // New tab button
            Button {
                appViewModel.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
                    .frame(width: 32, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("新しいタブ (⌘T)")
        }
        .frame(height: 34)
        .background(Color.kobaSurface)
        .overlay(Rectangle().fill(Color.kobaLine).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Single tab item

struct TabItemView: View {
    let tab: EditorTab
    @Environment(AppViewModel.self) private var appViewModel
    @State private var isHovered = false

    var isActive: Bool { appViewModel.activeTabID == tab.id }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tab.url == nil ? "doc" : "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(isActive ? Color.kobaAccent : Color.kobaMute)

            Text(tab.title)
                .font(.system(size: 12))
                .foregroundStyle(isActive ? Color.kobaInk : Color.kobaMute)
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)

            // 未保存ドット ↔ 閉じるボタン
            ZStack {
                if tab.isDirty && !isHovered {
                    Circle()
                        .fill(Color.kobaAccent)
                        .frame(width: 5, height: 5)
                }
                if isHovered {
                    Button {
                        appViewModel.closeTab(id: tab.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.kobaMute)
                    }
                    .buttonStyle(.plain)
                    .help("タブを閉じる (⌘W)")
                }
            }
            .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(isActive ? Color.kobaPaper : Color.kobaSurface)
        .overlay(
            isActive
                ? Rectangle().fill(Color.kobaAccent).frame(height: 2)
                : Rectangle().fill(Color.clear).frame(height: 2),
            alignment: .bottom
        )
        .overlay(Rectangle().fill(Color.kobaLine).frame(width: 1), alignment: .trailing)
        .contentShape(Rectangle())
        .onTapGesture {
            appViewModel.switchToTab(id: tab.id)
        }
        .onHover { isHovered = $0 }
    }
}
