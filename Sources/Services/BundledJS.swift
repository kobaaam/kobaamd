import Foundation

// Reads bundled JS/CSS files from the app bundle.
// Falls back to empty string so CDN-dependent code degrades gracefully.
enum BundledJS {
    static func content(named filename: String) -> String {
        guard let url = Bundle.module.url(forResource: filename, withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }

    // Lazily loaded — parsed once per app session
    static let mermaid: String    = content(named: "mermaid.min.js")
    static let easymdeJS: String  = content(named: "easymde.min.js")
    static let easymdeCss: String = content(named: "easymde.min.css")
    static let svgPanZoom: String = content(named: "svg-pan-zoom.min.js")
}
