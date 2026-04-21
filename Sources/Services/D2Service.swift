import Foundation

final class D2Service {
    private let fileManager = FileManager.default

    private let candidatePaths = [
        "/opt/homebrew/bin/d2",
        "/usr/local/bin/d2"
    ]

    func isD2Installed() -> Bool {
        d2BinaryPath() != nil
    }

    func d2BinaryPath() -> String? {
        candidatePaths.first { fileManager.fileExists(atPath: $0) }
    }

    func renderSVG(code: String) async throws -> String {
        guard let binaryPath = d2BinaryPath() else {
            throw D2Error.notInstalled
        }

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["-"]

            let inPipe = Pipe()
            let outPipe = Pipe()
            let errPipe = Pipe()

            process.standardInput = inPipe
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                inPipe.fileHandleForWriting.write(Data(code.utf8))
                try? inPipe.fileHandleForWriting.close()
                process.waitUntilExit()
            } catch {
                throw D2Error.renderFailed(error.localizedDescription)
            }

            let output = String(
                data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            let errOutput = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            guard process.terminationStatus == 0 else {
                let message = errOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                throw D2Error.renderFailed(message.isEmpty ? "D2のSVGレンダリングに失敗しました。" : message)
            }

            return output
        }.value
    }
}

enum D2Error: LocalizedError {
    case notInstalled
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "D2がインストールされていません。\n`brew install d2` でインストールしてください。"
        case .renderFailed(let message):
            return message
        }
    }
}
