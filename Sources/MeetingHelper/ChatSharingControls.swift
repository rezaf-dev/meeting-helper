import SwiftUI
import AppKit
import MeetingCore

struct CopyTextButton: View {
    let text: String
    var label = "Copy"
    @ViewState private var result: String?
    @ViewState private var feedbackTask: Task<Void, Never>?

    var body: some View {
        Button {
            let clipboard = NSPasteboard.general
            clipboard.clearContents()
            result = clipboard.setString(text, forType: .string) ? "Copied" : "Copy failed"
            feedbackTask?.cancel()
            feedbackTask = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                result = nil
            }
        } label: { Label(result ?? label, systemImage: result == "Copied" ? "checkmark" : "doc.on.doc") }
        .disabled(text.isEmpty)
        .accessibilityLabel(result ?? label)
        .onDisappear { feedbackTask?.cancel(); result = nil }
    }
}

struct ChatSharingControls: View {
    @ObservedObject var model: MeetingModel
    let chat: SavedChat
    private var snapshot: SavedChat { chat.id == model.currentChatID ? model.sessionSnapshot : chat }

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(ChatTextKind.allCases) { kind in
                    CopyTextButton(text: snapshot.text(for: kind), label: kind.label)
                }
            } label: { Label("Copy", systemImage: "doc.on.doc") }
            Menu {
                ForEach(ChatTextKind.allCases) { kind in
                    Button(kind.label) { model.exportText(kind, chat: chat) }
                        .disabled(snapshot.text(for: kind).isEmpty)
                }
            } label: { Label("Export…", systemImage: "square.and.arrow.up") }
        }.fixedSize()
    }
}
