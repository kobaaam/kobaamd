import Foundation
import Markdown

final class ConfluenceService {

    struct PageMapping: Codable {
        var spaceKey: String
        var parentPageId: String?
        var pageTitle: String
        var pageId: String?
    }

    private static var mappingsURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/kobaamd", isDirectory: true)
        return dir.appendingPathComponent("confluence_mappings.json")
    }

    private static func ensureMappingsDirectory() throws {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/kobaamd", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func loadMapping(for fileURL: URL) -> PageMapping? {
        guard let data = try? Data(contentsOf: Self.mappingsURL),
              let dict = try? JSONDecoder().decode([String: PageMapping].self, from: data) else { return nil }
        return dict[fileURL.path]
    }

    func saveMapping(_ mapping: PageMapping, for fileURL: URL) throws {
        try Self.ensureMappingsDirectory()
        var dict: [String: PageMapping] = [:]
        if let data = try? Data(contentsOf: Self.mappingsURL) {
            dict = (try? JSONDecoder().decode([String: PageMapping].self, from: data)) ?? [:]
        }
        dict[fileURL.path] = mapping
        let encoded = try JSONEncoder().encode(dict)
        try encoded.write(to: Self.mappingsURL, options: .atomic)
    }

    // MARK: - Markdown → Confluence Storage Format

    func convertToStorageFormat(_ markdown: String) -> String {
        let document = Document(parsing: markdown)
        var walker = StorageFormatWalker()
        walker.visit(document)
        return walker.result
    }

    // MARK: - Connection Test

    func testConnection(baseURL: String, email: String, apiToken: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/wiki/rest/api/space?limit=1") else {
            throw ConfluenceError.invalidURL
        }
        var req = URLRequest(url: url)
        req.setValue(basicAuth(email: email, token: apiToken), forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ConfluenceError.apiError(statusCode: code) }
        return true
    }

    // MARK: - Sync

    func syncPage(fileURL: URL, markdownContent: String) async throws {
        guard let baseURL = APIKeyStore.load(for: .confluenceURL), !baseURL.isEmpty,
              let email = APIKeyStore.load(for: .confluenceEmail), !email.isEmpty,
              let token = APIKeyStore.load(for: .confluenceToken), !token.isEmpty else {
            throw ConfluenceError.notConfigured
        }
        guard var mapping = loadMapping(for: fileURL) else {
            throw ConfluenceError.mappingNotFound
        }
        let storageContent = convertToStorageFormat(markdownContent)
        let auth = basicAuth(email: email, token: token)

        if let existingId = mapping.pageId, !existingId.isEmpty {
            // GET current version
            guard let getURL = URL(string: "\(baseURL)/wiki/rest/api/content/\(existingId)?expand=version") else {
                throw ConfluenceError.invalidURL
            }
            var getReq = URLRequest(url: getURL)
            getReq.setValue(auth, forHTTPHeaderField: "Authorization")
            let (getData, getResp) = try await URLSession.shared.data(for: getReq)
            let getCode = (getResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(getCode) else { throw ConfluenceError.apiError(statusCode: getCode) }
            struct VersionResp: Decodable {
                struct V: Decodable { var number: Int }
                var version: V
            }
            let vr = try JSONDecoder().decode(VersionResp.self, from: getData)
            let newVersion = vr.version.number + 1

            let body: [String: Any] = [
                "version": ["number": newVersion],
                "title": mapping.pageTitle,
                "type": "page",
                "body": ["storage": ["value": storageContent, "representation": "storage"]]
            ]
            guard let putURL = URL(string: "\(baseURL)/wiki/rest/api/content/\(existingId)") else {
                throw ConfluenceError.invalidURL
            }
            var putReq = URLRequest(url: putURL)
            putReq.httpMethod = "PUT"
            putReq.setValue(auth, forHTTPHeaderField: "Authorization")
            putReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            putReq.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, putResp) = try await URLSession.shared.data(for: putReq)
            let code = (putResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw ConfluenceError.apiError(statusCode: code) }
        } else {
            // POST new page
            var body: [String: Any] = [
                "type": "page",
                "title": mapping.pageTitle,
                "space": ["key": mapping.spaceKey],
                "body": ["storage": ["value": storageContent, "representation": "storage"]]
            ]
            if let parentId = mapping.parentPageId, !parentId.isEmpty {
                body["ancestors"] = [["id": parentId]]
            }
            guard let postURL = URL(string: "\(baseURL)/wiki/rest/api/content") else {
                throw ConfluenceError.invalidURL
            }
            var postReq = URLRequest(url: postURL)
            postReq.httpMethod = "POST"
            postReq.setValue(auth, forHTTPHeaderField: "Authorization")
            postReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            postReq.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (postData, postResp) = try await URLSession.shared.data(for: postReq)
            let code = (postResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw ConfluenceError.apiError(statusCode: code) }
            struct CreateResp: Decodable { var id: String }
            let created = try JSONDecoder().decode(CreateResp.self, from: postData)
            mapping.pageId = created.id
            try saveMapping(mapping, for: fileURL)
        }
    }

    private func basicAuth(email: String, token: String) -> String {
        let cred = Data("\(email):\(token)".utf8).base64EncodedString()
        return "Basic \(cred)"
    }
}

// MARK: - Confluence Storage Format Walker

private struct StorageFormatWalker: MarkupWalker {
    var result: String = ""

    mutating func visitDocument(_ document: Document) {
        descendInto(document)
    }

    mutating func visitHeading(_ heading: Heading) {
        let tag = "h\(heading.level)"
        result += "<\(tag)>"
        descendInto(heading)
        result += "</\(tag)>"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        result += "<p>"
        descendInto(paragraph)
        result += "</p>"
    }

    mutating func visitText(_ text: Text) {
        result += escapeXML(text.string)
    }

    mutating func visitStrong(_ strong: Strong) {
        result += "<strong>"
        descendInto(strong)
        result += "</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        result += "<em>"
        descendInto(emphasis)
        result += "</em>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code>\(escapeXML(inlineCode.code))</code>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let lang = codeBlock.language ?? "none"
        let escapedCode = codeBlock.code.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")
        result += "<ac:structured-macro ac:name=\"code\">"
        result += "<ac:parameter ac:name=\"language\">\(lang)</ac:parameter>"
        result += "<ac:plain-text-body><![CDATA[\(escapedCode)]]></ac:plain-text-body>"
        result += "</ac:structured-macro>"
    }

    mutating func visitLink(_ link: Link) {
        let dest = link.destination ?? ""
        result += "<a href=\"\(dest)\">"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitImage(_ image: Image) {
        let src = image.source ?? ""
        result += "<ac:image><ri:url ri:value=\"\(src)\"/></ac:image>"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        result += "<ul>"
        descendInto(unorderedList)
        result += "</ul>"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        result += "<ol>"
        descendInto(orderedList)
        result += "</ol>"
    }

    mutating func visitListItem(_ listItem: ListItem) {
        result += "<li>"
        descendInto(listItem)
        result += "</li>"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        result += "<hr/>"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        result += "<br/>"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        result += " "
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        result += "<blockquote>"
        descendInto(blockQuote)
        result += "</blockquote>"
    }

    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) {
        result += htmlBlock.rawHTML
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        result += inlineHTML.rawHTML
    }

    private func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Errors

enum ConfluenceError: LocalizedError {
    case notConfigured
    case mappingNotFound
    case invalidURL
    case apiError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Confluence の接続設定が未完了です。設定（⌘,）から Base URL・Email・API Token を登録してください。"
        case .mappingNotFound:
            return "このファイルの Confluence ページが未設定です。「File > Confluence ページ設定...」で設定してください。"
        case .invalidURL:
            return "Confluence の Base URL が正しくありません。"
        case let .apiError(code):
            return "Confluence API エラー (\(code)): リクエストが失敗しました。"
        }
    }
}
