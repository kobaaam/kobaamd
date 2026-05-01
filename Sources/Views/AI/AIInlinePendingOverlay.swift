import SwiftUI

struct AIInlinePendingOverlay: View {
    @Environment(AppViewModel.self) private var appViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.kobaAccent)
                    .frame(width: 2)

                ScrollView {
                    Text(appViewModel.pendingAIText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.kobaInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .frame(maxHeight: 300)
            }
            .background(Color.kobaAccent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if appViewModel.isAIGenerating {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("AI 生成中...")
                        .font(.caption)
                        .foregroundStyle(Color.kobaMute)
                    Spacer()
                    Button {
                        appViewModel.rejectPendingAIText()
                    } label: {
                        Label("キャンセル", systemImage: "xmark")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.top, 6)
                .padding(.horizontal, 4)
            }

            if appViewModel.isAIPendingConfirmation {
                HStack(spacing: 12) {
                    Button {
                        appViewModel.acceptPendingAIText()
                    } label: {
                        Label("確定", systemImage: "checkmark")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.kobaAccent)
                    .keyboardShortcut(.return, modifiers: [])

                    Button {
                        appViewModel.rejectPendingAIText()
                    } label: {
                        Label("破棄", systemImage: "xmark")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])

                    Spacer()

                    Text("Enter: 確定  Esc: 破棄")
                        .font(.caption2)
                        .foregroundStyle(Color.kobaMute2)
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: 500)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.kobaLine.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
    }
}
