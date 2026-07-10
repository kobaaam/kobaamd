import Foundation

/// テスト用の一時ディレクトリを管理するヘルパー。
/// struct ではなく final class にすることで、テスト suite の破棄時に deinit が走りディレクトリを自動削除する。
final class TempWorkspace {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kobaamd-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// 指定相対パスにファイルを書き込む。中間ディレクトリも自動作成する。
    @discardableResult
    func write(_ content: String, to relativePath: String) throws -> URL {
        let dest = url(relativePath)
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }

    /// 指定相対パスにディレクトリを作成する。
    @discardableResult
    func makeDir(_ relativePath: String) throws -> URL {
        let dest = url(relativePath)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        return dest
    }

    /// root からの相対パスを絶対 URL に変換する。
    func url(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }
}
