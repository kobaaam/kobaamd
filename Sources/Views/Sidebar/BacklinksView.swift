import SwiftUI

struct BacklinksView: View {
    @Environment(AppViewModel.self) private var appViewModel
    let backlinksViewModel: BacklinksViewModel
    @State private var hoveredID: UUID? = nil

    var body: some View {
        Group {
            if backlinksViewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if backlinksViewModel.linked.isEmpty && backlinksViewModel.unlinked.isEmpty && backlinksViewModel.hasAnthropicKey {
                VStack {
                    Spacer()
                    Text("Backlinks が見つかりません")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kobaMute)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        subsectionHeader("LINKED", count: backlinksViewModel.linked.count)

                        if backlinksViewModel.linked.isEmpty {
                            subsectionPlaceholder("Backlinks が見つかりません")
                        } else {
                            ForEach(backlinksViewModel.linked) { backlink in
                                linkedRow(backlink)
                            }
                        }

                        subsectionHeader("UNLINKED", count: backlinksViewModel.unlinked.count)

                        if !backlinksViewModel.hasAnthropicKey {
                            subsectionPlaceholder("API キー未設定")
                        } else if backlinksViewModel.unlinked.isEmpty {
                            subsectionPlaceholder("Backlinks が見つかりません")
                        } else {
                            ForEach(backlinksViewModel.unlinked) { backlink in
                                unlinkedRow(backlink)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color.kobaSidebar)
    }

    private func subsectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.kobaMute2)

            Text("(\(count))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(count > 0 ? Color.kobaInk : Color.kobaMute2)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }

    private func subsectionPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color.kobaMute)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func linkedRow(_ backlink: Backlink) -> some View {
        Button {
            Task { @MainActor in
                await appViewModel.openFileAndJump(url: backlink.sourceURL, line: backlink.line)
            }
        } label: {
            rowContent(backlink: backlink)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44, alignment: .leading)
                .background(
                    hoveredID == backlink.id
                        ? Color.kobaInk.opacity(0.06)
                        : Color.clear
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredID = hovering ? backlink.id : (hoveredID == backlink.id ? nil : hoveredID)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(backlink.sourceURL.lastPathComponent) \(backlink.line)行目 \(backlink.snippet)")
    }

    private func unlinkedRow(_ backlink: Backlink) -> some View {
        HStack(spacing: 0) {
            Button {
                Task { @MainActor in
                    await appViewModel.openFileAndJump(url: backlink.sourceURL, line: backlink.line)
                }
            } label: {
                rowContent(backlink: backlink)
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await backlinksViewModel.convertToLink(backlink)
                }
            } label: {
                Text("Convert to link")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.kobaAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.kobaAccent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .background(
            hoveredID == backlink.id
                ? Color.kobaInk.opacity(0.06)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredID = hovering ? backlink.id : (hoveredID == backlink.id ? nil : hoveredID)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(backlink.sourceURL.lastPathComponent) \(backlink.line)行目 \(backlink.snippet) Convert to link ボタン付き")
    }

    private func rowContent(backlink: Backlink) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(backlink.sourceURL.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.kobaInk)
                    .lineLimit(1)

                Text("L\(backlink.line)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.kobaMute2)
            }

            Text(backlink.snippet)
                .font(.system(size: 11))
                .foregroundStyle(Color.kobaMute)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
