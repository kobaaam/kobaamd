// Tools/SnapshotRunnerMain.swift
// Standalone snapshot test runner — bypasses swift test (broken on CommandLineTools).
// Built as a separate SPM executable target that depends on kobaamdLib.

import AppKit
import SwiftUI
import Foundation
@testable import kobaamdLib

// MARK: - Snapshot Helper (inlined — referenceDir uses CWD, not #filePath)

enum SnapshotHelper {
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

    static var referenceDir: URL {
        let projectDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return projectDir
            .appendingPathComponent("Tests")
            .appendingPathComponent("kobaamdTests")
            .appendingPathComponent("__Snapshots__")
    }

    @MainActor
    static func assertSnapshot<V: View>(
        _ view: V,
        size: CGSize,
        name: String,
        record: Bool = false
    ) throws -> (matched: Bool, message: String) {
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

        let failDir = refDir.appendingPathComponent("_failures")
        try FileManager.default.createDirectory(at: failDir, withIntermediateDirectories: true)
        try pngData.write(to: failDir.appendingPathComponent("\(name)_actual.png"))
        try referenceData.write(to: failDir.appendingPathComponent("\(name)_expected.png"))

        return (false, "Snapshot mismatch: \(name). See _failures/ for diff.")
    }
}

// MARK: - Test Registry

struct SnapshotTestCase {
    let name: String
    let run: @MainActor () throws -> (matched: Bool, message: String)
}

@MainActor
func buildTests() -> [SnapshotTestCase] {
    let record = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "true"
    return [
        SnapshotTestCase(name: "HelpContentView_gettingStarted") { @MainActor in
            let view = HelpContentView(section: .gettingStarted)
            return try SnapshotHelper.assertSnapshot(
                view,
                size: CGSize(width: 800, height: 600),
                name: "HelpContentView_gettingStarted",
                record: record
            )
        },
        SnapshotTestCase(name: "HelpContentView_shortcuts") { @MainActor in
            let view = HelpContentView(section: .shortcuts)
            return try SnapshotHelper.assertSnapshot(
                view,
                size: CGSize(width: 800, height: 600),
                name: "HelpContentView_shortcuts",
                record: record
            )
        },
        SnapshotTestCase(name: "TemplatePickerView") { @MainActor in
            let view = TemplatePickerView(isPresented: .constant(true))
                .environment(AppViewModel())
            return try SnapshotHelper.assertSnapshot(
                view,
                size: CGSize(width: 440, height: 360),
                name: "TemplatePickerView",
                record: record
            )
        },
        SnapshotTestCase(name: "FindReplaceBar") { @MainActor in
            let view = FindReplaceBar(
                isVisible: .constant(true),
                text: .constant("sample text for find replace")
            )
            return try SnapshotHelper.assertSnapshot(
                view,
                size: CGSize(width: 800, height: 52),
                name: "FindReplaceBar",
                record: record
            )
        },
    ]
}

// MARK: - Entry Point

@main
struct SnapshotRunner {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        DispatchQueue.main.async { @MainActor in
            var passed = 0
            var failed = 0
            var errors: [(String, String)] = []

            let tests = buildTests()

            for test in tests {
                do {
                    let result = try test.run()
                    if result.matched {
                        print("  ✅ \(test.name): \(result.message)")
                        passed += 1
                    } else {
                        print("  ❌ \(test.name): \(result.message)")
                        failed += 1
                        errors.append((test.name, result.message))
                    }
                } catch {
                    print("  💥 \(test.name): \(error)")
                    failed += 1
                    errors.append((test.name, "\(error)"))
                }
            }

            print("")
            print("Results: \(passed) passed, \(failed) failed, \(tests.count) total")

            if !errors.isEmpty {
                print("")
                print("Failures:")
                for (name, msg) in errors {
                    print("  - \(name): \(msg)")
                }
            }

            fflush(stdout)
            _Exit(failed > 0 ? 1 : 0)
        }

        app.run()
    }
}
