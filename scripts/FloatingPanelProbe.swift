import AppKit
import Foundation

@main
enum FloatingPanelProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 320),
                            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
        FloatingPanelPolicy.apply(to: panel, requestCaptureExclusion: true)
        precondition(panel.level == .floating)
        precondition(panel.isFloatingPanel && !panel.hidesOnDeactivate)
        precondition(panel.collectionBehavior.contains(.canJoinAllSpaces))
        precondition(panel.collectionBehavior.contains(.canJoinAllApplications))
        precondition(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        precondition(!panel.collectionBehavior.contains(.primary))
        precondition(panel.sharingType == .none)
        FloatingPanelPolicy.apply(to: panel, requestCaptureExclusion: false)
        precondition(panel.sharingType == .readOnly)
        precondition(panel.collectionBehavior.contains(.canJoinAllSpaces))
        print("PASS: native panel flags, inactive-app visibility, all-Spaces/full-screen eligibility, and capture-hint toggle")
        print("This checks configuration only; it does not establish exclusion from any actual screen share.")
    }
}
