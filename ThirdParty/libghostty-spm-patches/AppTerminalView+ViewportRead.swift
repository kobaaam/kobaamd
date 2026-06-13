#if canImport(AppKit) && !canImport(UIKit)
    import AppKit

    extension AppTerminalView {
        /// Snapshot of the visible terminal grid for agent-state heuristics.
        public func readViewportText() -> String? {
            surface?.readViewportText()
        }
    }
#endif