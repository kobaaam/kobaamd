import Foundation

struct DocumentTemplate: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let content: String
    let isBuiltIn: Bool

    /// frontmatter の title / description を抽出する。なければファイル名を返す。
    static func parse(filename: String, content: String, isBuiltIn: Bool) -> DocumentTemplate {
        var title = filename
        var description = ""

        if content.hasPrefix("---") {
            let lines = content.components(separatedBy: "\n")
            var inFrontmatter = false
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces) == "---" {
                    if inFrontmatter { break }
                    inFrontmatter = true
                    continue
                }
                if inFrontmatter {
                    if line.hasPrefix("title:") {
                        title = line.replacingOccurrences(of: "title:", with: "").trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("description:") {
                        description = line.replacingOccurrences(of: "description:", with: "").trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        return DocumentTemplate(
            id: filename,
            title: title,
            description: description,
            content: content,
            isBuiltIn: isBuiltIn
        )
    }
}
