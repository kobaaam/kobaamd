import Testing
@testable import kobaamd

@Suite("D2WebView Smoke")
@MainActor
struct D2WebViewTests {
    @Test("D2WebView を初期化できる")
    func initialization() {
        let vm = D2PreviewViewModel()
        let view = D2WebView(d2Code: "x -> y", viewModel: vm)

        #expect(view.d2Code == "x -> y")
    }

    @Test("sanitizeSVG が script タグを除去する")
    func sanitizeRemovesScript() {
        let vm = D2PreviewViewModel()
        let view = D2WebView(d2Code: "", viewModel: vm)
        let sanitized = view.sanitizeSVG(#"<svg><script>alert(1)</script><rect/></svg>"#)

        #expect(sanitized == "<svg><rect/></svg>")
    }

    @Test("空入力で pendingCode がクリアされる")
    func emptyInputClearsPending() async {
        let vm = D2PreviewViewModel()
        vm.pendingCode = "old"

        vm.update(text: "")

        #expect(vm.pendingCode == "")
        #expect(vm.isRendering == false)
    }

    @Test("非空入力で 300ms debounce 後に pendingCode が更新される")
    func debouncedUpdate() async throws {
        let vm = D2PreviewViewModel()

        vm.update(text: "a -> b")
        try await Task.sleep(nanoseconds: 400_000_000)
        await Task.yield()

        #expect(vm.pendingCode == "a -> b")
        #expect(vm.isRendering == true)
    }
}
