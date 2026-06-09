import AppKit

/// エディタ・プレビューのカラーテーマ定義。
/// Single Source of Truth — 色が必要な箇所はすべてここから取得する。
enum ColorTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case solarizedDark

    var id: String { rawValue }

    /// E1 ターミナル・エディタ・シェルの推奨テーマ（Gemini E1 / VS Code 系）。
    static let e1Recommended: ColorTheme = .dark

    var displayName: String {
        switch self {
        case .light:         return "Light"
        case .dark:          return "Dark"
        case .solarizedDark: return "Solarized Dark"
        }
    }

    var settingsCaption: String? {
        switch self {
        case .dark: return "E1 推奨（ターミナル・エディタ統一）"
        default: return nil
        }
    }

    // MARK: - Editor Colors

    var editorBackground: NSColor {
        switch self {
        case .light:         return NSColor(srgbRed: 0.992, green: 0.988, blue: 0.973, alpha: 1)
        case .dark:          return NSColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 1) // #1e1e1e
        case .solarizedDark: return NSColor(srgbRed: 0.0,   green: 0.169, blue: 0.212, alpha: 1) // #002b36
        }
    }

    var editorText: NSColor {
        switch self {
        case .light:         return NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1) // #1a1a1a
        case .dark:          return NSColor(srgbRed: 0.831, green: 0.831, blue: 0.831, alpha: 1) // #d4d4d4
        case .solarizedDark: return NSColor(srgbRed: 0.514, green: 0.580, blue: 0.588, alpha: 1) // #839496
        }
    }

    /// E1 ターミナルのデフォルト前景色。エディタより一段ソフトにして長時間の眩しさを抑える。
    var terminalForeground: NSColor {
        switch self {
        case .light:         return NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1) // #1a1a1a
        case .dark:          return NSColor(srgbRed: 0.706, green: 0.706, blue: 0.706, alpha: 1) // #b4b4b4
        case .solarizedDark: return NSColor(srgbRed: 0.514, green: 0.580, blue: 0.588, alpha: 1) // #839496
        }
    }

    /// E1 ターミナル用 16 色 ANSI パレット（VS Code Dark+ 系、白系のみ抑えめ）。
    var terminalAnsiPalette: [NSColor] {
        switch self {
        case .light:
            return [
                NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                NSColor(srgbRed: 0.804, green: 0.192, blue: 0.192, alpha: 1),
                NSColor(srgbRed: 0.051, green: 0.737, blue: 0.475, alpha: 1),
                NSColor(srgbRed: 0.898, green: 0.898, blue: 0.063, alpha: 1),
                NSColor(srgbRed: 0.141, green: 0.447, blue: 0.784, alpha: 1),
                NSColor(srgbRed: 0.737, green: 0.247, blue: 0.737, alpha: 1),
                NSColor(srgbRed: 0.067, green: 0.659, blue: 0.804, alpha: 1),
                NSColor(srgbRed: 0.706, green: 0.706, blue: 0.706, alpha: 1),
                NSColor(srgbRed: 0.4, green: 0.4, blue: 0.4, alpha: 1),
                NSColor(srgbRed: 0.945, green: 0.298, blue: 0.298, alpha: 1),
                NSColor(srgbRed: 0.137, green: 0.820, blue: 0.545, alpha: 1),
                NSColor(srgbRed: 0.961, green: 0.961, blue: 0.263, alpha: 1),
                NSColor(srgbRed: 0.231, green: 0.557, blue: 0.918, alpha: 1),
                NSColor(srgbRed: 0.839, green: 0.439, blue: 0.839, alpha: 1),
                NSColor(srgbRed: 0.161, green: 0.722, blue: 0.859, alpha: 1),
                NSColor(srgbRed: 0.784, green: 0.784, blue: 0.784, alpha: 1),
            ]
        case .dark:
            return [
                NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                NSColor(srgbRed: 0.804, green: 0.192, blue: 0.192, alpha: 1),
                NSColor(srgbRed: 0.051, green: 0.737, blue: 0.475, alpha: 1),
                NSColor(srgbRed: 0.898, green: 0.898, blue: 0.063, alpha: 1),
                NSColor(srgbRed: 0.141, green: 0.447, blue: 0.784, alpha: 1),
                NSColor(srgbRed: 0.737, green: 0.247, blue: 0.737, alpha: 1),
                NSColor(srgbRed: 0.067, green: 0.659, blue: 0.804, alpha: 1),
                NSColor(srgbRed: 0.706, green: 0.706, blue: 0.706, alpha: 1), // #b4b4b4
                NSColor(srgbRed: 0.4, green: 0.4, blue: 0.4, alpha: 1),
                NSColor(srgbRed: 0.945, green: 0.298, blue: 0.298, alpha: 1),
                NSColor(srgbRed: 0.137, green: 0.820, blue: 0.545, alpha: 1),
                NSColor(srgbRed: 0.961, green: 0.961, blue: 0.263, alpha: 1),
                NSColor(srgbRed: 0.231, green: 0.557, blue: 0.918, alpha: 1),
                NSColor(srgbRed: 0.839, green: 0.439, blue: 0.839, alpha: 1),
                NSColor(srgbRed: 0.161, green: 0.722, blue: 0.859, alpha: 1),
                NSColor(srgbRed: 0.784, green: 0.784, blue: 0.784, alpha: 1), // #c8c8c8
            ]
        case .solarizedDark:
            return [
                NSColor(srgbRed: 0.027, green: 0.212, blue: 0.259, alpha: 1),
                NSColor(srgbRed: 0.863, green: 0.196, blue: 0.184, alpha: 1),
                NSColor(srgbRed: 0.522, green: 0.600, blue: 0.0, alpha: 1),
                NSColor(srgbRed: 0.710, green: 0.537, blue: 0.0, alpha: 1),
                NSColor(srgbRed: 0.149, green: 0.545, blue: 0.824, alpha: 1),
                NSColor(srgbRed: 0.424, green: 0.443, blue: 0.769, alpha: 1),
                NSColor(srgbRed: 0.149, green: 0.616, blue: 0.604, alpha: 1),
                NSColor(srgbRed: 0.514, green: 0.580, blue: 0.588, alpha: 1),
                NSColor(srgbRed: 0.345, green: 0.431, blue: 0.459, alpha: 1),
                NSColor(srgbRed: 0.863, green: 0.196, blue: 0.184, alpha: 1),
                NSColor(srgbRed: 0.522, green: 0.600, blue: 0.0, alpha: 1),
                NSColor(srgbRed: 0.710, green: 0.537, blue: 0.0, alpha: 1),
                NSColor(srgbRed: 0.149, green: 0.545, blue: 0.824, alpha: 1),
                NSColor(srgbRed: 0.424, green: 0.443, blue: 0.769, alpha: 1),
                NSColor(srgbRed: 0.149, green: 0.616, blue: 0.604, alpha: 1),
                NSColor(srgbRed: 0.576, green: 0.631, blue: 0.631, alpha: 1),
            ]
        }
    }

    var editorCurrentLineHighlight: NSColor {
        switch self {
        case .light:         return NSColor(srgbRed: 0.918, green: 0.910, blue: 0.890, alpha: 1)
        case .dark:          return NSColor(srgbRed: 0.16,  green: 0.16,  blue: 0.16,  alpha: 1)
        case .solarizedDark: return NSColor(srgbRed: 0.027, green: 0.212, blue: 0.259, alpha: 1) // #073642
        }
    }

    // MARK: - Syntax Colors

    var headingColor: NSColor {
        switch self {
        case .light:         return NSColor(srgbRed: 0.102, green: 0.102, blue: 0.102, alpha: 1)
        case .dark:          return NSColor(srgbRed: 0.914, green: 0.914, blue: 0.914, alpha: 1)
        case .solarizedDark: return NSColor(srgbRed: 0.710, green: 0.537, blue: 0.0,   alpha: 1) // #b58900
        }
    }

    var codeColor: NSColor {
        switch self {
        case .light:         return NSColor(srgbRed: 0.18,  green: 0.56,  blue: 0.27,  alpha: 1)
        case .dark:          return NSColor(srgbRed: 0.42,  green: 0.75,  blue: 0.42,  alpha: 1)
        case .solarizedDark: return NSColor(srgbRed: 0.522, green: 0.600, blue: 0.0,   alpha: 1) // #859900
        }
    }

    var linkColor: NSColor {
        switch self {
        case .light:         return NSColor(srgbRed: 0.0,   green: 0.44,  blue: 0.87,  alpha: 1)
        case .dark:          return NSColor(srgbRed: 0.34,  green: 0.61,  blue: 0.94,  alpha: 1)
        case .solarizedDark: return NSColor(srgbRed: 0.149, green: 0.545, blue: 0.824, alpha: 1) // #268bd2
        }
    }

    var accentColor: NSColor {
        switch self {
        case .light:         return NSColor(srgbRed: 1.0,   green: 0.357, blue: 0.122, alpha: 1) // #FF5B1F
        case .dark:          return NSColor(srgbRed: 1.0,   green: 0.45,  blue: 0.25,  alpha: 1)
        case .solarizedDark: return NSColor(srgbRed: 0.796, green: 0.294, blue: 0.086, alpha: 1) // #cb4b16
        }
    }

    var mutedColor: NSColor {
        switch self {
        case .light:         return NSColor(srgbRed: 0.55,  green: 0.55,  blue: 0.55,  alpha: 1)
        case .dark:          return NSColor(srgbRed: 0.60,  green: 0.60,  blue: 0.60,  alpha: 1)
        case .solarizedDark: return NSColor(srgbRed: 0.396, green: 0.482, blue: 0.514, alpha: 1) // #657b83
        }
    }

    var purpleColor: NSColor {
        switch self {
        case .light:         return NSColor(srgbRed: 0.55,  green: 0.27,  blue: 0.82,  alpha: 1)
        case .dark:          return NSColor(srgbRed: 0.68,  green: 0.45,  blue: 0.92,  alpha: 1)
        case .solarizedDark: return NSColor(srgbRed: 0.424, green: 0.443, blue: 0.769, alpha: 1) // #6c71c4
        }
    }

    var redColor: NSColor {
        switch self {
        case .light:         return NSColor(srgbRed: 0.75,  green: 0.20,  blue: 0.17,  alpha: 1)
        case .dark:          return NSColor(srgbRed: 0.85,  green: 0.35,  blue: 0.30,  alpha: 1)
        case .solarizedDark: return NSColor(srgbRed: 0.863, green: 0.196, blue: 0.184, alpha: 1) // #dc322f
        }
    }

    // MARK: - Preview CSS

    var previewCSS: String {
        switch self {
        case .light:
            return """
            *{box-sizing:border-box}
            html{background:#fdfcf8}
            body{
              font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;
              font-size:15px;
              line-height:1.75;
              color:#1a1a1a;
              max-width:720px;
              margin:0 auto;
              padding:32px 28px 80px;
              background:#fdfcf8;
              -webkit-font-smoothing:antialiased;
            }
            h1,h2,h3,h4,h5,h6{
              font-weight:700;
              line-height:1.3;
              margin:1.6em 0 0.5em;
              color:#111;
            }
            h1{font-size:2em;margin-top:0.8em}
            h2{font-size:1.4em;border-bottom:2px solid #e8e5df;padding-bottom:0.25em}
            h3{font-size:1.15em}
            p{margin:0.8em 0}
            a{color:#0070f3;text-decoration:none}
            a:hover{text-decoration:underline}
            strong{font-weight:700}
            em{font-style:italic}
            del{color:#999}
            code{
              font-family:"SF Mono",Menlo,Monaco,monospace;
              font-size:0.88em;
              background:#eeecea;
              padding:2px 5px;
              border-radius:4px;
              color:#c0392b;
            }
            pre{
              background:#f0ede8;
              border:1px solid #e0ddd8;
              border-radius:8px;
              padding:16px 20px;
              overflow-x:auto;
              margin:1.2em 0;
            }
            pre code{
              background:none;
              padding:0;
              color:#1a1a1a;
              font-size:0.87em;
            }
            blockquote{
              border-left:3px solid #FF5B1F;
              margin:1em 0;
              padding:4px 0 4px 18px;
              color:#555;
              font-style:italic;
            }
            img{max-width:100%;border-radius:6px}
            hr{border:none;border-top:1px solid #e0ddd8;margin:2em 0}
            table{border-collapse:collapse;width:100%;margin:1.2em 0;font-size:0.93em}
            th,td{border:1px solid #e0ddd8;padding:8px 14px;text-align:left}
            th{background:#f5f2ec;font-weight:600}
            tr:nth-child(even) td{background:#faf8f4}
            ul,ol{padding-left:1.6em;margin:0.8em 0}
            li{margin:0}
            li p{margin:0}
            li:has(input[type=checkbox]){list-style:none;margin-left:-1.6em}
            li input[type=checkbox]{margin-right:6px;accent-color:#FF5B1F;vertical-align:middle}
            [data-source-line-start]{cursor:pointer}
            [data-koba-active]{background-color:rgba(255,91,31,0.08);border-radius:4px}
            tr[data-koba-active] td,tr[data-koba-active] th{background-color:rgba(255,91,31,0.08)}
            """

        case .dark:
            return """
            *{box-sizing:border-box}
            html{background:#1e1e1e}
            body{
              font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;
              font-size:15px;
              line-height:1.75;
              color:#d4d4d4;
              max-width:720px;
              margin:0 auto;
              padding:32px 28px 80px;
              background:#1e1e1e;
              -webkit-font-smoothing:antialiased;
            }
            h1,h2,h3,h4,h5,h6{
              font-weight:700;
              line-height:1.3;
              margin:1.6em 0 0.5em;
              color:#e9e9e9;
            }
            h1{font-size:2em;margin-top:0.8em}
            h2{font-size:1.4em;border-bottom:2px solid #333;padding-bottom:0.25em}
            h3{font-size:1.15em}
            p{margin:0.8em 0}
            a{color:#569cd6;text-decoration:none}
            a:hover{text-decoration:underline}
            strong{font-weight:700}
            em{font-style:italic}
            del{color:#666}
            code{
              font-family:"SF Mono",Menlo,Monaco,monospace;
              font-size:0.88em;
              background:#2d2d2d;
              padding:2px 5px;
              border-radius:4px;
              color:#d9594c;
            }
            pre{
              background:#252526;
              border:1px solid #333;
              border-radius:8px;
              padding:16px 20px;
              overflow-x:auto;
              margin:1.2em 0;
            }
            pre code{
              background:none;
              padding:0;
              color:#d4d4d4;
              font-size:0.87em;
            }
            blockquote{
              border-left:3px solid #ff7340;
              margin:1em 0;
              padding:4px 0 4px 18px;
              color:#999;
              font-style:italic;
            }
            img{max-width:100%;border-radius:6px}
            hr{border:none;border-top:1px solid #333;margin:2em 0}
            table{border-collapse:collapse;width:100%;margin:1.2em 0;font-size:0.93em}
            th,td{border:1px solid #333;padding:8px 14px;text-align:left}
            th{background:#2a2a2a;font-weight:600}
            tr:nth-child(even) td{background:#252526}
            ul,ol{padding-left:1.6em;margin:0.8em 0}
            li{margin:0}
            li p{margin:0}
            li:has(input[type=checkbox]){list-style:none;margin-left:-1.6em}
            li input[type=checkbox]{margin-right:6px;accent-color:#ff7340;vertical-align:middle}
            [data-source-line-start]{cursor:pointer}
            [data-koba-active]{background-color:rgba(255,115,64,0.12);border-radius:4px}
            tr[data-koba-active] td,tr[data-koba-active] th{background-color:rgba(255,115,64,0.12)}
            """

        case .solarizedDark:
            return """
            *{box-sizing:border-box}
            html{background:#002b36}
            body{
              font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;
              font-size:15px;
              line-height:1.75;
              color:#839496;
              max-width:720px;
              margin:0 auto;
              padding:32px 28px 80px;
              background:#002b36;
              -webkit-font-smoothing:antialiased;
            }
            h1,h2,h3,h4,h5,h6{
              font-weight:700;
              line-height:1.3;
              margin:1.6em 0 0.5em;
              color:#b58900;
            }
            h1{font-size:2em;margin-top:0.8em}
            h2{font-size:1.4em;border-bottom:2px solid #073642;padding-bottom:0.25em}
            h3{font-size:1.15em}
            p{margin:0.8em 0}
            a{color:#268bd2;text-decoration:none}
            a:hover{text-decoration:underline}
            strong{font-weight:700}
            em{font-style:italic}
            del{color:#657b83}
            code{
              font-family:"SF Mono",Menlo,Monaco,monospace;
              font-size:0.88em;
              background:#073642;
              padding:2px 5px;
              border-radius:4px;
              color:#dc322f;
            }
            pre{
              background:#073642;
              border:1px solid #586e75;
              border-radius:8px;
              padding:16px 20px;
              overflow-x:auto;
              margin:1.2em 0;
            }
            pre code{
              background:none;
              padding:0;
              color:#839496;
              font-size:0.87em;
            }
            blockquote{
              border-left:3px solid #cb4b16;
              margin:1em 0;
              padding:4px 0 4px 18px;
              color:#657b83;
              font-style:italic;
            }
            img{max-width:100%;border-radius:6px}
            hr{border:none;border-top:1px solid #586e75;margin:2em 0}
            table{border-collapse:collapse;width:100%;margin:1.2em 0;font-size:0.93em}
            th,td{border:1px solid #586e75;padding:8px 14px;text-align:left}
            th{background:#073642;font-weight:600}
            tr:nth-child(even) td{background:#073642}
            ul,ol{padding-left:1.6em;margin:0.8em 0}
            li{margin:0}
            li p{margin:0}
            li:has(input[type=checkbox]){list-style:none;margin-left:-1.6em}
            li input[type=checkbox]{margin-right:6px;accent-color:#cb4b16;vertical-align:middle}
            [data-source-line-start]{cursor:pointer}
            [data-koba-active]{background-color:rgba(203,75,22,0.15);border-radius:4px}
            tr[data-koba-active] td,tr[data-koba-active] th{background-color:rgba(203,75,22,0.15)}
            """
        }
    }
}
