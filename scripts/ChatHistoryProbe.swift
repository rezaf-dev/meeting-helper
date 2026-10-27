import AppKit
import MeetingCore

/// Runs against a temporary archive. No capture, network calls, or real chat files.
@main
struct ChatHistoryProbe {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingHelper-history-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = MeetingModel(chatDirectory: directory)
        model.notes = "Notes that must survive quitting"
        model.replyDraft = "Draft reply"
        model.assistanceTitle = "Test answer"
        model.assistance = "Original answer"
        try await Task.sleep(for: .milliseconds(650))
        let firstID = model.currentChatID
        let count1 = try ChatStore(directory: directory).load().count
        precondition(count1 == 1)
        let restored = MeetingModel(chatDirectory: directory)
        precondition(restored.notes == model.notes)
        precondition(restored.replyDraft == model.replyDraft)
        precondition(restored.assistanceHistory.entries.first?.text == "Original answer")
        precondition(restored.currentChatID == firstID)
        model.clearSession()
        precondition(model.currentChatID != firstID)
        precondition(model.notes.isEmpty && model.assistance.isEmpty)
        model.notes = "Second chat"
        precondition(model.saveChat())
        let count2 = try ChatStore(directory: directory).load().count
        precondition(count2 == 2)
        model.deleteChat(firstID)
        let remaining = try ChatStore(directory: directory).load().count
        precondition(remaining == 1)
        model.deleteChat(model.currentChatID)
        try await Task.sleep(for: .milliseconds(650))
        let empty = try ChatStore(directory: directory).load().isEmpty
        precondition(empty)
        precondition(model.notes.isEmpty)
        let exportDirectory = directory.appendingPathComponent("export-check")
        let epoch = Date(timeIntervalSince1970: 1000)
        let captions = (0..<650).map {
            Caption(source: .system, text: "Full transcript sentence \($0)", start: Double($0), end: Double($0 + 1),
                    timestamp: epoch.addingTimeInterval(Double($0)), isFinal: true)
        }
        try ChatStore(directory: exportDirectory).save(SavedChat(captions: captions))
        let exportModel = MeetingModel(chatDirectory: exportDirectory)
        precondition(exportModel.ledger.finalized.count == 500)
        precondition(exportModel.sessionSnapshot.captions.count == 650)
        precondition(exportModel.sessionSnapshot.transcriptText.contains("Full transcript sentence 0"))
        exportModel.assistance = "Fresh answer before autosave"
        precondition(exportModel.sessionSnapshot.answersText.contains("Fresh answer before autosave"))
        exportModel.archiveAssistance()
        exportModel.assistance = "Next answer"
        precondition(exportModel.sessionSnapshot.answers.count == 2)
        let exported = exportModel.sessionSnapshot.text(for: .session)
        let exportedURL = directory.appendingPathComponent("session.txt")
        try exported.write(to: exportedURL, atomically: true, encoding: .utf8)
        let readBack = try String(contentsOf: exportedURL, encoding: .utf8)
        precondition(readBack == exported)
        print("PASS: complete transcript beyond 500 captions, latest answers, UTF-8 export")
        print("PASS: autosave, restart restoration, new chat, and permanent deletion without resurrection")
    }
}
