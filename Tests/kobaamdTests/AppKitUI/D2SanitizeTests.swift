import Testing
@testable import kobaamd

@Suite("D2 SVG Sanitization")
@MainActor
struct D2SanitizeTests {
    private let view = D2WebView(d2Code: "", viewModel: D2PreviewViewModel())

    @Test("script タグが除去されること")
    func removesScriptTag() {
        let svg = #"<svg><script>alert('xss')</script><rect/></svg>"#
        let sanitized = view.sanitizeSVG(svg)

        #expect(!sanitized.contains("<script"))
        #expect(sanitized == "<svg><rect/></svg>")
    }

    @Test("大文字の SCRIPT タグも除去されること")
    func removesUppercaseScriptTag() {
        let svg = #"<svg><SCRIPT>alert(1)</SCRIPT><rect/></svg>"#
        let sanitized = view.sanitizeSVG(svg)

        #expect(!sanitized.localizedCaseInsensitiveContains("<script"))
        #expect(sanitized == "<svg><rect/></svg>")
    }

    @Test("属性付き script タグが除去されること")
    func removesScriptTagWithAttributes() {
        let svg = #"<svg><script type="text/javascript">alert(1)</script><rect/></svg>"#
        let sanitized = view.sanitizeSVG(svg)

        #expect(!sanitized.contains("text/javascript"))
        #expect(sanitized == "<svg><rect/></svg>")
    }

    @Test("改行を含む script タグが除去されること")
    func removesMultilineScriptTag() {
        let svg = """
        <svg><script>
        alert(1)
        </script><rect/></svg>
        """
        let sanitized = view.sanitizeSVG(svg)

        #expect(!sanitized.contains("alert(1)"))
        #expect(sanitized == "<svg><rect/></svg>")
    }

    @Test("自己閉じ script タグが除去されること")
    func removesSelfClosingScriptTag() {
        let svg = #"<svg><script src="x.js"/><rect/></svg>"#
        let sanitized = view.sanitizeSVG(svg)

        #expect(!sanitized.contains("x.js"))
        #expect(sanitized == "<svg><rect/></svg>")
    }

    @Test("通常の SVG は変更されないこと")
    func keepsSafeSVG() {
        let svg = "<svg><rect/></svg>"
        #expect(view.sanitizeSVG(svg) == svg)
    }

    @Test("イベントハンドラ属性が除去されること")
    func removesEventHandlerAttributes() {
        let svg = #"<svg onload="alert(1)"><rect onclick='alert(2)'/></svg>"#
        let sanitized = view.sanitizeSVG(svg)

        #expect(!sanitized.contains("onload="))
        #expect(!sanitized.contains("onclick="))
        #expect(sanitized == "<svg><rect/></svg>")
    }
}
