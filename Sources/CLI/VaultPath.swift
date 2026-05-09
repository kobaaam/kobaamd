import Foundation

struct VaultPath: Sendable {
    enum Error: Swift.Error {
        case outsideVault
        case invalid
    }

    let vaultRoot: URL

    func resolve(_ path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Error.invalid
        }

        let root = vaultRoot.standardizedFileURL
        let candidate: URL

        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
        } else {
            candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        }

        let rootPath = root.path
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            throw Error.outsideVault
        }

        return candidate
    }
}
