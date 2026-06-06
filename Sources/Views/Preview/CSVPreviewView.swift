import SwiftUI

/// CSV ファイルのプレビュー View（読み取り専用テーブル表示）。
/// D2PreviewView と同じパターンで AppViewModel.editorText を購読し、
/// CSVPreviewViewModel 経由でパース結果を受け取る。
struct CSVPreviewView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var csvVM = CSVPreviewViewModel()

    var body: some View {
        Group {
            if csvVM.table.headers.isEmpty && csvVM.table.rows.isEmpty {
                // パース結果が空の場合のプレースホルダ
                VStack(spacing: 8) {
                    Text("CSV が空です")
                        .foregroundStyle(Color.kobaMute)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.kobaSurface)
            } else {
                CSVTableView(table: csvVM.table)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: appViewModel.editorText) { _, newValue in
            csvVM.update(text: newValue)
        }
        .onChange(of: appViewModel.selectedFileURL) { _, _ in
            csvVM.updateImmediate(text: appViewModel.editorText)
        }
        .onAppear {
            csvVM.updateImmediate(text: appViewModel.editorText)
        }
    }
}

// MARK: - CSVTableView

/// スクロール可能なグリッドでテーブルを描画する内部 View。
/// 行数・列数が多い場合に備えて LazyVStack を使用する。
private struct CSVTableView: View {
    let table: CSVTable

    // セルの最小幅・最大幅
    private let minCellWidth: CGFloat = 60
    private let maxCellWidth: CGFloat = 280
    private let rowHeight: CGFloat = 28
    private let headerHeight: CGFloat = 32

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                // ヘッダ行
                Section {
                    // データ行（zebra ストライプ）
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                        CSVRowView(
                            rowNumber: rowIndex + 1,
                            cells: row,
                            columnCount: table.columnCount,
                            minCellWidth: minCellWidth,
                            maxCellWidth: maxCellWidth,
                            height: rowHeight,
                            isHeader: false,
                            isEven: rowIndex % 2 == 0
                        )
                        Divider()
                            .background(Color.kobaLine)
                    }

                    // 切り捨て通知
                    if table.isTruncated {
                        HStack {
                            Text("表示上限（\(CSVParser.maxRows) 行）を超えたため、一部の行を省略しています。")
                                .font(.caption)
                                .foregroundStyle(Color.kobaMute)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            Spacer()
                        }
                        .background(Color.kobaAccentSoft)
                    }
                } header: {
                    // ヘッダ行（スクロール時も固定）
                    CSVRowView(
                        rowNumber: nil,
                        cells: table.headers,
                        columnCount: table.columnCount,
                        minCellWidth: minCellWidth,
                        maxCellWidth: maxCellWidth,
                        height: headerHeight,
                        isHeader: true,
                        isEven: false
                    )
                    Divider()
                        .background(Color.kobaAccent.opacity(0.3))
                }
            }
        }
        .background(Color.kobaPaper)
    }
}

// MARK: - CSVRowView

/// 1 行分のセル群を HStack で描画するコンポーネント。
private struct CSVRowView: View {
    /// 行番号（nil のときは行番号列を空白で描画）
    let rowNumber: Int?
    let cells: [String]
    let columnCount: Int
    let minCellWidth: CGFloat
    let maxCellWidth: CGFloat
    let height: CGFloat
    let isHeader: Bool
    let isEven: Bool

    // 行番号列の固定幅
    private let rowNumberWidth: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            // 行番号列
            Group {
                if let n = rowNumber {
                    Text("\(n)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.kobaMute2)
                        .frame(width: rowNumberWidth, height: height, alignment: .trailing)
                        .padding(.trailing, 6)
                } else {
                    // ヘッダ行では行番号列を空欄にする
                    Color.clear
                        .frame(width: rowNumberWidth, height: height)
                }
            }

            // セル群（columnCount に合わせて不足分は空セルで補完）
            ForEach(0 ..< columnCount, id: \.self) { colIndex in
                let text = colIndex < cells.count ? cells[colIndex] : ""
                CSVCellView(
                    text: text,
                    isHeader: isHeader,
                    minWidth: minCellWidth,
                    maxWidth: maxCellWidth,
                    height: height
                )
                // 列区切り線
                if colIndex < columnCount - 1 {
                    Divider()
                        .background(Color.kobaLine)
                        .frame(height: height)
                }
            }
        }
        .background(rowBackground)
    }

    private var rowBackground: Color {
        if isHeader {
            return Color.kobaSidebar
        }
        return isEven ? Color.kobaPaper : Color.kobaSurface
    }
}

// MARK: - CSVCellView

/// 1 セル分のテキスト表示。テキスト選択コピーを有効にする。
private struct CSVCellView: View {
    let text: String
    let isHeader: Bool
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let height: CGFloat

    var body: some View {
        Text(text)
            .font(isHeader ? .system(size: 12, weight: .semibold) : .system(size: 12))
            .foregroundStyle(isHeader ? Color.kobaInk : Color.kobaInk.opacity(0.85))
            .lineLimit(1)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .frame(minWidth: minWidth, maxWidth: maxWidth, minHeight: height, maxHeight: height, alignment: .leading)
            .padding(.horizontal, 8)
    }
}
