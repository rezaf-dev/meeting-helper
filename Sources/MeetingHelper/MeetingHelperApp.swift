import SwiftUI
import AppKit

@main
struct MeetingHelperApp: App {
    @NSApplicationDelegateAdaptor(MeetingApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = MeetingModel()

    var body: some Scene {
        WindowGroup("MeetingHelper", id: "main") {
            MeetingView(model: model)
                .frame(minWidth: 980, minHeight: 800)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if ProcessInfo.processInfo.arguments.contains("--demo") { model.loadDemo() }
                }
        }
        .defaultSize(width: 1180, height: 860)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.showSettings = true }.keyboardShortcut(",")
            }
            CommandMenu("Meeting") {
                Button("Chat history…") { model.openHistory() }.keyboardShortcut("h", modifiers: [.command, .option])
                Button("New chat") { model.clearSession() }.keyboardShortcut("n")
                    .disabled(model.isRunning || model.isBusy)
                Divider()
                Button(model.isRunning ? "Stop captions" : "Start captions") {
                    Task { if model.isRunning { await model.stop() } else { await model.start() } }
                }.keyboardShortcut("l", modifiers: [.command, .shift]).disabled(model.isBusy)
                Button("Explain that") { model.analyze(.explain) }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Help me reply") { model.analyze(.reply) }.keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button(model.floatingIsVisible ? "Hide floating captions" : "Show floating captions") {
                    model.toggleFloatingCaptions()
                }.keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("MeetingHelper", systemImage: model.isRunning ? "waveform" : "captions.bubble") {
            MeetingMenu(model: model)
        }
    }
}

@MainActor
final class MeetingApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        // Updating a locally built bundle can leave Launch Services' previous generic icon cached.
        // Set the running application's Dock icon explicitly as well as declaring the bundle icon.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            app.applicationIconImage = image
            app.dockTile.display()
        }
    }
}

private struct MeetingMenu: View {
    @ObservedObject var model: MeetingModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Show MeetingHelper") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button(model.isRunning ? "Stop captions" : "Start captions") {
            Task { if model.isRunning { await model.stop() } else { await model.start() } }
        }.disabled(model.isBusy)
        Button(model.floatingIsVisible ? "Hide floating captions" : "Show floating captions") {
            model.toggleFloatingCaptions()
        }
        Divider()
        Text(model.status)
        Button("Quit MeetingHelper") { NSApplication.shared.terminate(nil) }
    }
}
