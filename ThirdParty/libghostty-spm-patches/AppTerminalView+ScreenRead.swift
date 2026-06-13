#if canImport(AppKit) && !canImport(UIKit)
    import AppKit

    extension AppTerminalView {
        /// Snapshot of viewport + scrollback for transcript capture.
        public func readScreenText() -> String? {
            surface?.readScreenText()
        }
    }
#endif