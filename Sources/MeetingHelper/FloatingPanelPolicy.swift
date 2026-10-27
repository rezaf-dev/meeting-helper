import AppKit

@MainActor
enum FloatingPanelPolicy {
    static func apply(to panel: NSPanel, requestCaptureExclusion: Bool) {
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications,
                                    .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // This is a legacy compatibility hint, not a capture-prevention guarantee.
        // Modern ScreenCaptureKit-based sharing can still include the panel.
        panel.sharingType = requestCaptureExclusion ? .none : .readOnly
    }
}
