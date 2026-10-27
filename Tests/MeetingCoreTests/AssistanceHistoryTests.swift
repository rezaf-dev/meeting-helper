import Foundation
import Testing
@testable import MeetingCore

struct AssistanceHistoryTests {
    @Test func newAnswersDoNotEvictEarlierRepliesAndRepeatedWordsStayDistinct() {
        var history = AssistanceHistory()
        let first = AssistanceRecord(title: "Help me reply", text: "Please clarify the scope.", model: "test/model")
        history.retain(first)
        for _ in 0..<250 {
            history.retain(AssistanceRecord(title: "Live help", text: first.text, model: "test/model"))
        }
        #expect(history.entries.count == 251)
        #expect(history.entries.first == first)
        history.retain(first)
        #expect(history.entries.count == 251)
    }

    @Test func interruptedAndFailedAnswersRemainExportableAndClearIsExplicit() {
        var history = AssistanceHistory()
        history.retain(AssistanceRecord(title: "Reply", text: "I need to check", model: "test/one", status: .partial))
        history.retain(AssistanceRecord(title: "Explanation", text: "Ballpark means rough estimate.", model: "test/two", status: .failed))
        history.retain(AssistanceRecord(title: "Empty", text: " \n", model: "test/three"))
        #expect(history.entries.count == 2)
        #expect(history.exportText.contains("I need to check"))
        #expect(history.exportText.contains("Ballpark means rough estimate."))
        #expect(history.exportText.contains("(partial)"))
        #expect(history.exportText.contains("(failed)"))
        #expect(history.exportText.contains("test/two"))
        history.clear()
        #expect(history.entries.isEmpty)
        #expect(history.exportText.isEmpty)
    }
}
