// Auto-increment this build number on every release build.
// Semantic version follows Phase milestones:
//   0.x = pre-release / Phase 2
//   1.0 = Phase 3 complete, OSS release

enum AppVersion {
    static let semantic = "0.3.2"
    static let build    = 5
    static var display: String { "v\(semantic) (b\(build))" }
}
