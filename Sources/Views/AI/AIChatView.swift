import SwiftUI

struct AIChatView: View {
    @Bindable var viewModel: AIChatViewModel
    var onInsertToEditor: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(Color.kobaAccent)
                Text("AI チャット")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kobaInk)
                Spacer()
                Picker("", selection: $viewModel.selectedProvider) {
                    ForEach(APIKeyStore.Provider.allCases.filter { $0.isAIProvider }, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.kobaSurface)
            .overlay(Rectangle().fill(Color.kobaLine).frame(height: 1), alignment: .bottom)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                onInsert: { onInsertToEditor(message.content) }
                            )
                            .id(message.id)
                        }

                        if viewModel.isLoading && !viewModel.streamingContent.isEmpty {
                            StreamingBubble(content: viewModel.streamingContent)
                                .id("streaming")
                        }

                        if viewModel.isLoading && viewModel.streamingContent.isEmpty {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("応答を生成中...")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.kobaMute)
                            }
                            .padding(12)
                            .id("loading")
                        }
                    }
                    .padding(10)
                }
                .accessibilityLabel("AI chat history")
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.streamingContent) { _, _ in
                    if viewModel.isLoading {
                        withAnimation {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.kobaMute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.kobaSurface)
                .overlay(Rectangle().fill(Color.kobaLine).frame(height: 1), alignment: .top)
            }

            VStack(spacing: 0) {
                Rectangle().fill(Color.kobaLine).frame(height: 1)
                HStack(spacing: 8) {
                    TextField("メッセージを入力...", text: $viewModel.inputText, axis: .vertical)
                        .lineLimit(1 ... 4)
                        .font(.system(size: 13))
                        .textFieldStyle(.plain)
                        .onSubmit {
                            viewModel.send()
                        }
                    Button {
                        viewModel.send()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 22, height: 22)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(
                                    viewModel.inputText.isEmpty ? Color.kobaMute : Color.kobaAccent
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                HStack {
                    Spacer()
                    Button("会話をクリア") {
                        viewModel.clearMessages()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.kobaMute)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .background(Color.kobaSurface)
        }
        .background(Color.kobaPaper)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let onInsert: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kobaInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                    .padding(10)
                    .background(
                        message.role == .user
                            ? Color.kobaAccent.opacity(0.12)
                            : Color.kobaSurface
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityValue(message.role == .user ? "ユーザーメッセージ" : "アシスタントメッセージ")

                if message.role == .assistant {
                    Button("エディタに挿入") {
                        onInsert()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.kobaMute)
                    .padding(.leading, 4)
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }
}

private struct StreamingBubble: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(content)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kobaInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.kobaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Spacer(minLength: 40)
        }
    }
}
