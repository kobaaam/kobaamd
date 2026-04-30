import SwiftUI

struct HelpContentView: View {
    let section: HelpSection

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(section.rawValue)
                .font(.title2)
                .bold()
                .foregroundStyle(Color.kobaInk)

            content(for: section)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func content(for section: HelpSection) -> some View {
        switch section {
        case .gettingStarted:
            sectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    bodyText("kobaamd は AI が生成した Markdown を Mac で最も快適に扱えるエディタです。")
                    bodyText("使い始め: ⌘O でフォルダを開く、または Finder から .md ファイルをダブルクリック。")
                    bodyText("エディタ左にサイドバー（⌘B で表示切替）、右にプレビューが表示されます。")
                }
            }

        case .shortcuts:
            sectionCard {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    ForEach(shortcuts, id: \.key) { item in
                        GridRow(alignment: .center) {
                            shortcutKey(item.key)
                            bodyText(item.description)
                                .gridCellAnchor(.leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .features:
            VStack(alignment: .leading, spacing: 16) {
                featureBlock(
                    title: "基本操作",
                    text: "フォルダを開いてMarkdownファイルを編集。タブで複数ファイル同時編集。サイドバーでファイルツリー・検索・TODO・アウトライン管理。"
                )
                featureBlock(
                    title: "プレビューモード",
                    text: "エディタのみ / スプリットビュー（左エディタ・右プレビュー）を切り替え。Markdownをリアルタイムレンダリング。"
                )
                featureBlock(
                    title: "クイックオープン",
                    text: "⌘P でファイル名インクリメンタル検索。"
                )
                featureBlock(
                    title: "テンプレート",
                    text: "⌘⇧N で README、日記、会議メモ、技術仕様書など AI フレンドリーなテンプレートから新規ファイル作成。"
                )
                featureBlock(
                    title: "検索・置換",
                    text: "⌘F でファイル内検索。正規表現対応。"
                )
                featureBlock(
                    title: "ドキュメント整形",
                    text: "⌘⇧F で見出し・空行・リストを自動正規化。"
                )
            }

        case .ai:
            VStack(alignment: .leading, spacing: 16) {
                featureBlock(
                    title: "AI アシスト（⌘E）",
                    text: "テキストを選択して AI に書き換え・翻訳・要約を依頼。"
                )
                featureBlock(
                    title: "AI チャット（⌘⇧E）",
                    text: "サイドバーで AI とマルチターン会話。現在のドキュメントをコンテキストとして共有。"
                )
                featureBlock(
                    title: "AI インライン補完",
                    text: "{{プロンプト}} 記法で Cmd+Return するとその場で AI が文章を生成。ストリーミング対応。"
                )
                featureBlock(
                    title: "クイックインサート（⌘K）",
                    text: "AI プロンプトスニペットをワンキーで挿入。"
                )
            }

        case .integrations:
            VStack(alignment: .leading, spacing: 16) {
                featureBlock(
                    title: "Mermaid ダイアグラム",
                    text: "コードブロック内に mermaid 記法を書くとリアルタイムプレビュー。"
                )
                featureBlock(
                    title: "D2 ダイアグラム",
                    text: "d2 記法にも対応（要 brew install d2）。"
                )
                featureBlock(
                    title: "Confluence 同期（⌘⇧U）",
                    text: "Markdown を Confluence ページとして同期。API トークンを設定画面で登録。"
                )
                featureBlock(
                    title: "PDF 書き出し（⌘⇧P）",
                    text: "現在のプレビューをPDFとしてエクスポート。"
                )
                featureBlock(
                    title: "Diff ビュー",
                    text: "ファイル変更の差分をレンダリング済み Markdown で表示。"
                )
                featureBlock(
                    title: "カラーテーマ",
                    text: "設定画面からエディタ・プレビューのカラーテーマを選択。"
                )
            }

        case .faq:
            sectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    faqItem(
                        question: "AI アシストが動かない",
                        answer: "設定画面で API キーと API エンドポイントを正しく設定してください。"
                    )
                    faqItem(
                        question: "Mermaid がレンダリングされない",
                        answer: "コードブロックの言語指定が ```mermaid であることを確認してください。"
                    )
                    faqItem(
                        question: "Confluence 同期に失敗する",
                        answer: "設定画面で Confluence URL・ユーザー名・API トークンが正しいか確認してください。"
                    )
                    faqItem(
                        question: "D2 が表示されない",
                        answer: "brew install d2 で d2 コマンドをインストールしてください。"
                    )
                }
            }
        }
    }

    private var shortcuts: [(key: String, description: String)] {
        [
            ("⌘O", "フォルダを開く"),
            ("⌘N", "新規ファイル"),
            ("⌘⇧N", "テンプレートから新規作成"),
            ("⌘T", "新しいタブ"),
            ("⌘W", "タブを閉じる"),
            ("⌘S", "保存"),
            ("⌘F", "検索・置換"),
            ("⌘⇧F", "ドキュメント整形"),
            ("⌘B", "サイドバー表示切替"),
            ("⌘E", "AI アシスト"),
            ("⌘⇧E", "AI チャット"),
            ("⌘.", "AI 生成キャンセル"),
            ("⌘K", "クイックインサート"),
            ("⌘P", "クイックオープン"),
            ("⌘⇧P", "PDF 書き出し"),
            ("⌘⇧U", "Confluence 同期"),
            ("⌘,", "設定")
        ]
    }

    @ViewBuilder
    private func featureBlock(title: String, text: String) -> some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.kobaInk)
                bodyText(text)
            }
        }
    }

    @ViewBuilder
    private func faqItem(question: String, answer: String) -> some View {
        DisclosureGroup {
            bodyText(answer)
                .padding(.top, 4)
        } label: {
            Text(question)
                .font(.headline)
                .foregroundStyle(Color.kobaInk)
        }
        .tint(Color.kobaAccent)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.kobaSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.kobaLine, lineWidth: 1)
            )
    }

    private func shortcutKey(_ key: String) -> some View {
        Text(key)
            .font(.system(.body, design: .monospaced, weight: .semibold))
            .foregroundStyle(Color.kobaInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.kobaAccentSoft)
            )
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Color.kobaMute)
            .fixedSize(horizontal: false, vertical: true)
    }
}
