// Auto-increment this build number on every release build.
// Semantic version follows Phase milestones:
//   0.x = pre-release / Phase 2
//   1.0 = Phase 3 complete, OSS release

enum AppVersion {
    static let semantic = "0.3.4"
    static let build    = 7
    static var display: String { "v\(semantic) (b\(build))" }
}
