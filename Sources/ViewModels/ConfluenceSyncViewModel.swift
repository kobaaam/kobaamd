import Foundation
import Observation

@Observable
@MainActor
final class ConfluenceSyncViewModel {
    var syncStatusMessage: String? = nil
    var isSyncing: Bool = false
    var isPageSettingSheetPresented: Bool = false
    var currentFileURL: URL? = nil

    // deinit は actor isolation を受けないため nonisolated(unsafe) が必要（@Observable マクロの mutable 制約による）
    nonisolated(unsafe) private var statusTask: Task<Void, Never>? = nil

    deinit {
        statusTask?.cancel()
    }

    // MARK: - Mapping (View 経由アクセス用)

    func loadMapping(for fileURL: URL) -> ConfluenceService.PageMapping? {
        ConfluenceService().loadMapping(for: fileURL)
    }

    func saveMapping(_ mapping: ConfluenceService.PageMapping, for fileURL: URL) throws {
        try ConfluenceService().saveMapping(mapping, for: fileURL)
    }

    func performSync(fileURL: URL?, markdownContent: String, onError: @MainActor @escaping (AppError) -> Void) {
        guard let fileURL else {
            onError(.unknown(underlying: NSError(
                domain: "Confluence",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "ファイルが保存されていません。先にファイルを保存してから同期してください。"]
            )))
            return
        }

        let service = ConfluenceService()

        // マッピング未設定チェック
        if service.loadMapping(for: fileURL) == nil {
            currentFileURL = fileURL
            isPageSettingSheetPresented = true
            return
        }

        // API Token 未設定チェック
        guard let token = APIKeyStore.load(for: .confluenceToken), !token.isEmpty else {
            onError(.unknown(underlying: ConfluenceError.notConfigured))
            return
        }

        isSyncing = true
        syncStatusMessage = "Confluence に同期中..."

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await service.syncPage(fileURL: fileURL, markdownContent: markdownContent)
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                self.syncStatusMessage = "Confluence に同期しました (\(formatter.string(from: Date())))"
                self.isSyncing = false
                self.statusTask?.cancel()
                self.statusTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    self?.syncStatusMessage = nil
                }
            } catch let e as ConfluenceError {
                self.isSyncing = false
                self.syncStatusMessage = nil
                if case .mappingNotFound = e {
                    self.currentFileURL = fileURL
                    self.isPageSettingSheetPresented = true
                } else {
                    onError(.unknown(underlying: e))
                }
            } catch {
                self.isSyncing = false
                self.syncStatusMessage = nil
                onError(.unknown(underlying: error))
            }
        }
    }
}
