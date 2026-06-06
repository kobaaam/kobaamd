import Foundation

/// Sparkle 自動アップデートが有効かどうか。
/// ローカル ad-hoc ビルド（`SUPublicEDKey` 未注入）では OFF にし、起動時エラーを防ぐ。
enum SparkleConfiguration {
    static var isConfigured: Bool {
        let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let feedURL = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !publicKey.isEmpty && !feedURL.isEmpty
    }
}