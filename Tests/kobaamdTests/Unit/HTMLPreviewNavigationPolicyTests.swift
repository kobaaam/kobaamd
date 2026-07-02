import Foundation
import Testing
import WebKit
@testable import kobaamd

/// LocalhostHTMLWebView.Coordinator.navigationPolicy の純関数テスト。
///
/// WKWebView を起動せず、ポリシー判定ロジックだけを検証する。
@Suite("HTML preview navigation policy")
@MainActor
struct HTMLPreviewNavigationPolicyTests {
    typealias Policy = LocalhostHTMLWebViewCoordinatorPolicy

    let previewURL = URL(string: "http://127.0.0.1:9123/index.html")!

    // MARK: - allow ケース

    @Test("about:blank は allow されること")
    func aboutBlankIsAllowed() {
        let url = URL(string: "about:blank")!
        let result = Policy.navigationPolicy(for: url, navigationType: .other, previewURL: previewURL)
        #expect(result == .allow)
    }

    @Test("other ナビゲーション（JS起点）で同一 origin は allow されること")
    func otherNavigationTypeIsAllowed() {
        let url = URL(string: "http://127.0.0.1:9123/subpage.html")!
        let result = Policy.navigationPolicy(for: url, navigationType: .other, previewURL: previewURL)
        #expect(result == .allow)
    }

    @Test("other ナビゲーション（JS起点: window.location=）で外部 https は cancel されること")
    func otherNavigationTypeExternalHttpsCancelled() {
        // window.location = 'https://evil.com' 等の JS 起点遷移は .other で届く。
        // 同一 origin 外なら cancel して DNS rebinding / open redirect を防ぐ。
        let url = URL(string: "https://evil.com")!
        let result = Policy.navigationPolicy(for: url, navigationType: .other, previewURL: previewURL)
        #expect(result == .cancel)
    }

    @Test("other ナビゲーション（JS起点）で別ドメインの http は cancel されること")
    func otherNavigationTypeExternalHttpCancelled() {
        let url = URL(string: "http://attacker.example.com/steal")!
        let result = Policy.navigationPolicy(for: url, navigationType: .other, previewURL: previewURL)
        #expect(result == .cancel)
    }

    @Test("reload ナビゲーションは allow されること")
    func reloadIsAllowed() {
        let url = URL(string: "http://127.0.0.1:9123/index.html")!
        let result = Policy.navigationPolicy(for: url, navigationType: .reload, previewURL: previewURL)
        #expect(result == .allow)
    }

    @Test("同一 origin（127.0.0.1 / 同じポート）への遷移は allow されること")
    func sameOriginNavigationIsAllowed() {
        let url = URL(string: "http://127.0.0.1:9123/assets/style.css")!
        let result = Policy.navigationPolicy(for: url, navigationType: .linkActivated, previewURL: previewURL)
        #expect(result == .allow)
    }

    // MARK: - cancel ケース

    @Test("linkActivated で外部 https URL は cancel されること")
    func externalHttpsLinkIsCancelled() {
        let url = URL(string: "https://example.com")!
        let result = Policy.navigationPolicy(for: url, navigationType: .linkActivated, previewURL: previewURL)
        #expect(result == .cancel)
    }

    @Test("linkActivated で外部 http URL は cancel されること")
    func externalHttpLinkIsCancelled() {
        let url = URL(string: "http://example.com/page")!
        let result = Policy.navigationPolicy(for: url, navigationType: .linkActivated, previewURL: previewURL)
        #expect(result == .cancel)
    }

    @Test("file: URL は cancel されること")
    func fileUrlIsCancelled() {
        let url = URL(string: "file:///etc/passwd")!
        let result = Policy.navigationPolicy(for: url, navigationType: .linkActivated, previewURL: previewURL)
        #expect(result == .cancel)
    }

    @Test("別ポートの 127.0.0.1 は異なる origin として cancel されること")
    func differentPortIsNotSameOrigin() {
        let url = URL(string: "http://127.0.0.1:8080/index.html")!
        let result = Policy.navigationPolicy(for: url, navigationType: .linkActivated, previewURL: previewURL)
        #expect(result == .cancel)
    }

    @Test("previewURL が nil のときは初期ロード安全弁として allow されること")
    func nilPreviewURLAllowsInitialNavigation() {
        let url = URL(string: "https://example.com")!
        let result = Policy.navigationPolicy(for: url, navigationType: .linkActivated, previewURL: nil)
        #expect(result == .allow)
    }

    @Test("blob: スキームは cancel されること")
    func blobUrlIsCancelled() {
        let url = URL(string: "blob:http://127.0.0.1:9123/abc123")!
        let result = Policy.navigationPolicy(for: url, navigationType: .linkActivated, previewURL: previewURL)
        #expect(result == .cancel)
    }
}
