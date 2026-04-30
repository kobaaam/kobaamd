import AppKit
import SwiftUI

enum SnapshotHelper {
    /// SwiftUI View をオフスクリーンレンダリングして PNG データを返す
    @MainActor
    static func render<V: View>(_ view: V, size: CGSize) -> Data? {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return nil
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    /// リファレンスディレクトリのパスを返す
    static var referenceDir: URL {
        // Tests/kobaamdTests/__Snapshots__/
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testDir.appendingPathComponent("__Snapshots__")
    }

    /// スナップショットをリファレンスと比較する
    /// リファレンスが存在しない場合は新規作成して true を返す（初回記録モード）
    @MainActor
    static func assertSnapshot<V: View>(
        _ view: V,
        size: CGSize,
        name: String,
        file: String = #filePath,
        record: Bool = false
    ) throws -> (matched: Bool, message: String) {
        _ = file

        guard let pngData = render(view, size: size) else {
            return (false, "Failed to render view")
        }

        let refDir = referenceDir
        let refFile = refDir.appendingPathComponent("\(name).png")

        if record || !FileManager.default.fileExists(atPath: refFile.path) {
            try FileManager.default.createDirectory(at: refDir, withIntermediateDirectories: true)
            try pngData.write(to: refFile)
            return (true, "Recorded snapshot: \(name).png")
        }

        let referenceData = try Data(contentsOf: refFile)
        if pngData == referenceData {
            return (true, "Snapshot matches: \(name)")
        }

        // 差分画像を保存
        let failDir = refDir.appendingPathComponent("_failures")
        try FileManager.default.createDirectory(at: failDir, withIntermediateDirectories: true)
        try pngData.write(to: failDir.appendingPathComponent("\(name)_actual.png"))
        try referenceData.write(to: failDir.appendingPathComponent("\(name)_expected.png"))

        return (false, "Snapshot mismatch: \(name). See _failures/ for diff.")
    }
}
