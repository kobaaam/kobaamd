import Foundation

/// エディタバッファとディスクのどちらを表示に使うか（外部エージェント更新の統一ルール）。
enum FileContentResolver {
    /// 未編集時はディスクを優先、編集中は in-memory バッファを返す。
    static func displayContent(url: URL?, inMemory: String, isDirty: Bool) -> String {
        guard !isDirty, let url else { return inMemory }
        guard FileManager.default.fileExists(atPath: url.path) else { return inMemory }
        if let disk = try? FileService().readFile(at: url) {
            return disk
        }
        return inMemory
    }
}