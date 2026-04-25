import Foundation
import Observation

@Observable
@MainActor
final class DiffViewModel {
    var textA: String = ""
    var textB: String = ""
    var fileNameA: String = ""
    var fileNameB: String = ""
    var lines: [DiffLine] = []

    private var debounceTask: Task<Void, Never>?

    struct DiffLine: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind

        enum Kind {
            case added
            case removed
            case context
            case header
        }
    }

    func scheduleUpdate() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.lines = await Self.computeDiff(a: self.textA, b: self.textB)
        }
    }

    private static func computeDiff(a: String, b: String) async -> [DiffLine] {
        let tmpA = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kobaamd_diff_a.txt")
        let tmpB = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kobaamd_diff_b.txt")
        try? a.write(to: tmpA, atomically: true, encoding: .utf8)
        try? b.write(to: tmpB, atomically: true, encoding: .utf8)

        return await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["diff", "--no-index", "--color=never", tmpA.path, tmpB.path]

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()

            try? proc.run()
            proc.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if output.isEmpty { return [] }

            return output.components(separatedBy: "\n").compactMap { raw in
                guard !raw.isEmpty else { return nil }

                if raw.hasPrefix("+++") || raw.hasPrefix("---") || raw.hasPrefix("diff") || raw.hasPrefix("index") {
                    return DiffViewModel.DiffLine(text: raw, kind: .header)
                } else if raw.hasPrefix("+") {
                    return DiffViewModel.DiffLine(text: raw, kind: .added)
                } else if raw.hasPrefix("-") {
                    return DiffViewModel.DiffLine(text: raw, kind: .removed)
                } else if raw.hasPrefix("@@") {
                    return DiffViewModel.DiffLine(text: raw, kind: .header)
                } else {
                    return DiffViewModel.DiffLine(text: raw, kind: .context)
                }
            }
        }.value
    }
}
