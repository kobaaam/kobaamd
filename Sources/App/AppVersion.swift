import Foundation

enum AppVersion {
    /// Info.plist のマーケティング版（`CFBundleShortVersionString`）。
    static var semantic: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Info.plist のビルド番号（`CFBundleVersion`）。
    static var build: Int {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let number = Int(raw) else { return 0 }
        return number
    }

    static var display: String { "v\(semantic) (b\(build))" }

    /// 後方互換エイリアス。
    static var bundleShort: String { semantic }

    static var bundleMarketing: String { "v\(semantic)" }
}