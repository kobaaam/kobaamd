import Testing
import SwiftUI
import Foundation
@testable import kobaamdLib

@Suite("Snapshot Tests")
@MainActor
struct SnapshotTests {
    /// SNAPSHOT_RECORD=true 環境変数 or true で初回リファレンス画像を生成
    private let recording = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "true"

    @Test("HelpContentView - Getting Started")
    func helpContentGettingStarted() throws {
        let view = HelpContentView(section: .gettingStarted)
        let result = try SnapshotHelper.assertSnapshot(
            view,
            size: CGSize(width: 800, height: 600),
            name: "HelpContentView_gettingStarted",
            record: recording
        )
        #expect(result.matched, "\(result.message)")
    }

    @Test("HelpContentView - Shortcuts")
    func helpContentShortcuts() throws {
        let view = HelpContentView(section: .shortcuts)
        let result = try SnapshotHelper.assertSnapshot(
            view,
            size: CGSize(width: 800, height: 600),
            name: "HelpContentView_shortcuts",
            record: recording
        )
        #expect(result.matched, "\(result.message)")
    }

    @Test("TemplatePickerView")
    func templatePicker() throws {
        let view = TemplatePickerView(isPresented: .constant(true))
            .environment(AppViewModel())
        let result = try SnapshotHelper.assertSnapshot(
            view,
            size: CGSize(width: 440, height: 360),
            name: "TemplatePickerView",
            record: recording
        )
        #expect(result.matched, "\(result.message)")
    }

    @Test("FindReplaceBar")
    func findReplaceBar() throws {
        let view = FindReplaceBar(
            isVisible: .constant(true),
            text: .constant("sample text for find replace")
        )
        let result = try SnapshotHelper.assertSnapshot(
            view,
            size: CGSize(width: 800, height: 52),
            name: "FindReplaceBar",
            record: recording
        )
        #expect(result.matched, "\(result.message)")
    }
}
