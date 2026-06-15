import Foundation

// Auto-increment this build number on every release build.
// Semantic version follows Phase milestones:
//   0.x = pre-release / Phase 2
//   1.0 = Phase 3 complete, OSS release

enum AppVersion {
    static let semantic = "0.4.4"
    static let build    = 44
    static var display: String { "v\(semantic) (b\(build))" }

    /// Info.plist のマーケティング版（インストール名と揃える）。
    static var bundleShort: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? semantic
    }

    static var bundleMarketing: String { "v\(bundleShort)" }
}
