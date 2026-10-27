import AppKit
import SwiftUI

@MainActor
final class CaptionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// AppKit owns the panel so attachment timing or SwiftUI window management cannot undo its behavior.
@MainActor
final class FloatingCaptionController: NSObject, NSWindowDelegate {
    private weak var model: MeetingModel?
    private var panel: CaptionPanel?

    init(model: MeetingModel) { self.model = model }

    func show() {
        guard let model else { return }
        let panel: CaptionPanel
        if let existing = self.panel { panel = existing }
        else {
            panel = CaptionPanel(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 320),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
                backing: .buffered, defer: false)
            panel.title = "Floating captions"
            panel.identifier = NSUserInterfaceItemIdentifier("MeetingHelper.FloatingCaptions")
            panel.minSize = NSSize(width: 420, height: 230)
            panel.isReleasedWhenClosed = false
            panel.isExcludedFromWindowsMenu = true
            panel.animationBehavior = .utilityWindow
            panel.contentView = NSHostingView(rootView: FloatingCaptions(model: model))
            panel.delegate = self
            if !panel.setFrameUsingName("MeetingHelper.FloatingCaptions") { panel.center() }
            panel.setFrameAutosaveName("MeetingHelper.FloatingCaptions")
            self.panel = panel
        }
        FloatingPanelPolicy.apply(to: panel, requestCaptureExclusion: model.settings.requestCaptureExclusion)
        panel.orderFrontRegardless()
        model.floatingIsVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        model?.floatingIsVisible = false
    }

    func setCaptureExclusion(_ requested: Bool) {
        guard let panel else { return }
        FloatingPanelPolicy.apply(to: panel, requestCaptureExclusion: requested)
    }

    func windowWillClose(_ notification: Notification) {
        model?.floatingIsVisible = false
    }
}
