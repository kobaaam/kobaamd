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

        // Resolve symlinks in vault root to get canonical path
        let root = vaultRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate: URL

        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardizedFileURL.resolvingSymlinksInPath()
        } else {
            candidate = root.appendingPathComponent(trimmed).standardizedFileURL.resolvingSymlinksInPath()
        }

        let rootPath = root.path
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            throw Error.outsideVault
        }

        return candidate
    }
}
