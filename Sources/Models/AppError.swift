import Foundation

enum AppError: LocalizedError {
    case fileReadFailed(url: URL, underlying: Error)
    case fileWriteFailed(url: URL, underlying: Error)
    case fileDeleteFailed(url: URL, underlying: Error)
    case fileRenameFailed(from: URL, to: URL, underlying: Error)
    case directoryLoadFailed(url: URL, underlying: Error)
    case unknown(underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .fileReadFailed(url, underlying):
            return "ファイルの読み込みに失敗しました: \(url.lastPathComponent)\n\(underlying.localizedDescription)"
        case let .fileWriteFailed(url, underlying):
            return "ファイルの書き込みに失敗しました: \(url.lastPathComponent)\n\(underlying.localizedDescription)"
        case let .fileDeleteFailed(url, underlying):
            return "ファイルの削除に失敗しました: \(url.lastPathComponent)\n\(underlying.localizedDescription)"
        case let .fileRenameFailed(from, to, underlying):
            return "ファイル名の変更に失敗しました: \(from.lastPathComponent) → \(to.lastPathComponent)\n\(underlying.localizedDescription)"
        case let .directoryLoadFailed(url, underlying):
            return "ディレクトリの読み込みに失敗しました: \(url.lastPathComponent)\n\(underlying.localizedDescription)"
        case let .unknown(underlying):
            return "不明なエラーが発生しました\n\(underlying.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fileReadFailed:    return "ファイルの権限や存在を確認してください。"
        case .fileWriteFailed:   return "書き込み先のディスク容量や権限を確認してください。"
        case .fileDeleteFailed:  return "ファイルが使用中でないか、権限があるか確認してください。"
        case .fileRenameFailed:  return "ファイル名の重複や権限を確認し、再試行してください。"
        case .directoryLoadFailed: return "ディレクトリのパスやアクセス権を確認してください。"
        case .unknown:           return "アプリを再起動するか、設定を見直してください。"
        }
    }
}
