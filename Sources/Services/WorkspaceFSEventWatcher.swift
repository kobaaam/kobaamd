import CoreServices
import Foundation

/// ワークスペース直下のファイルシステム変更を監視し、デバウンス後にコールバックする。
final class WorkspaceFSEventWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.kobaamd.fsevents", qos: .utility)
    private var debounceWorkItem: DispatchWorkItem?
    private var onChangeHandler: (@Sendable () -> Void)?

    func watch(urls: [URL], onChange: @escaping @Sendable () -> Void) {
        stop()
        let paths = urls.map(\.path)
        guard !paths.isEmpty else { return }

        onChangeHandler = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            UInt32(kFSEventStreamCreateFlagFileEvents)
                | UInt32(kFSEventStreamCreateFlagUseCFTypes)
                | UInt32(kFSEventStreamCreateFlagNoDefer)
        )

        guard let stream = FSEventStreamCreate(
            nil,
            Self.eventCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        onChangeHandler = nil

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }

    private func scheduleReload() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChangeHandler?()
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private static let eventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<WorkspaceFSEventWatcher>.fromOpaque(info).takeUnretainedValue()
        watcher.scheduleReload()
    }
}