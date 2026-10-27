import Foundation
import Testing
@testable import MeetingCore

struct ChatStoreTests {
    private func withStore(_ body: (ChatStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(ChatStore(directory: directory))
    }

    @Test func savesAndRestoresFullChatAcrossStoreInstances() throws {
        try withStore { store in
            let captions = (0..<600).map {
                Caption(source: .microphone, text: "Sentence \($0)", start: Double($0), end: Double($0 + 1), isFinal: true)
            }
            let answer = AssistanceRecord(title: "Reply", text: "Let me check.", model: "test/model", status: .partial,
                                          input: "Need more time; transcript and notes")
            let chat = SavedChat(captions: captions, answers: [answer], notes: "Scope", draft: "Maybe tomorrow", intent: "Ask for time")
            try store.save(chat)
            let restored = try ChatStore(directory: store.directory).load()
            #expect(restored == [chat])
            #expect(restored.first?.captions.count == 600)
        }
    }

    @Test func updatesAreAtomicAndDeletionDoesNotAffectOtherChats() throws {
        try withStore { store in
            var first = SavedChat(notes: "First")
            let second = SavedChat(updatedAt: Date().addingTimeInterval(10), notes: "Second")
            try store.save(first); try store.save(second)
            first.answers = [AssistanceRecord(title: "Explain", text: "Saved answer", model: "test")]
            try store.save(first)
            #expect(try store.load() == [second, first])
            try store.delete(id: first.id)
            #expect(try ChatStore(directory: store.directory).load() == [second])
            try store.delete(id: first.id)
        }
    }

    @Test func ignoresEmptyChatsAndPreservesUnreadableFiles() throws {
        try withStore { store in
            try store.save(SavedChat())
            #expect(try store.load().isEmpty)
            let chat = SavedChat(notes: "Readable")
            try store.save(chat)
            let damaged = store.directory.appendingPathComponent("damaged.json")
            try Data("broken".utf8).write(to: damaged)
            let report = try store.loadReport()
            #expect(report.chats == [chat])
            #expect(report.unreadableFiles == ["damaged.json"])
            #expect(try String(contentsOf: damaged, encoding: .utf8) == "broken")
        }
    }

    @Test func clearingSavedNotesDoesNotRestoreStaleText() throws {
        try withStore { store in
            var chat = SavedChat(notes: "Remove this text")
            try store.save(chat)
            chat.notes = ""
            try store.save(chat)
            #expect(try store.load().first?.notes == "")
        }
    }

    @Test func writeFailuresAreReportedAndRequestsWithoutOutputSurvive() throws {
        try withStore { store in
            var history = AssistanceHistory()
            history.retain(AssistanceRecord(title: "Reply", text: "", model: "test", status: .failed, input: "My request"))
            #expect(history.entries.count == 1)
            try Data("file in place of directory".utf8).write(to: store.directory)
            #expect(throws: (any Error).self) { try store.save(SavedChat(answers: history.entries)) }
        }
    }
}
