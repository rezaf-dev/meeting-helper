import Testing
import Foundation
@testable import MeetingCore

struct TranscriptTests {
    private func caption(_ text: String, start: Double = 0, end: Double = 2, final: Bool = false) -> Caption {
        caption(.system, text, start: start, end: end, final: final)
    }

    private func caption(_ source: AudioSource, _ text: String, start: Double = 0,
                         end: Double = 2, final: Bool = false) -> Caption {
        Caption(source: source, text: text, start: start, end: end,
                timestamp: Date(timeIntervalSince1970: start), isFinal: final)
    }

    @Test func testFinalizationReplacesHypothesisWithoutDuplicatingWords() {
        var ledger = TranscriptLedger()
        ledger.receive(caption("Can you give"))
        ledger.receive(caption("Can you give an estimate?"))
        #expect(ledger.displayed.count == 1)
        ledger.receive(caption("Can you give an estimate?", final: true))
        #expect(ledger.displayed.count == 1)
        #expect(ledger.context() == "[Meeting] Can you give an estimate?")
        #expect(ledger.partials.isEmpty)
    }

    @Test func testFinalizingOneSourceDoesNotEraseOtherSource() {
        var ledger = TranscriptLedger()
        ledger.receive(caption(.microphone, "I'm checking"))
        ledger.receive(caption(.system, "Can you check?", final: true))
        #expect(ledger.displayed.count == 2)
        #expect(ledger.partials[.microphone]?.text == "I'm checking")
    }

    @Test func testFinalUpdatesAreIdempotentAndLateHypothesesIgnored() {
        var ledger = TranscriptLedger()
        ledger.receive(caption("Thursday", final: true))
        let id = ledger.finalized.first?.id
        ledger.receive(caption("Tuesday", final: true))
        ledger.receive(caption("Thursday"))
        #expect(ledger.displayed.count == 1)
        #expect(ledger.finalized.first?.id == id)
        #expect(ledger.finalized.first?.text == "Tuesday")
    }

    @Test func testMemoryAndCloudContextAreBoundedAndExcludeVolatileText() {
        var ledger = TranscriptLedger(capacity: 2)
        ledger.receive(caption("Old", start: 0, final: true))
        ledger.receive(caption("Middle", start: 3, end: 4, final: true))
        ledger.receive(caption("Latest", start: 5, end: 6, final: true))
        ledger.receive(caption(.microphone, "Uncertain", start: 8, end: 9))
        #expect(ledger.finalized.count == 2)
        #expect(!ledger.context().contains("Old"))
        #expect(!ledger.context().contains("Uncertain"))
        #expect(ledger.context(maxCharacters: 16) == "[Meeting] Latest")
        #expect(ledger.context(maxCharacters: 4).count <= 4)
        #expect(ledger.context(maxCharacters: 0) == "")
    }

    @Test func testArrivalOrderDoesNotChangeChronologicalContext() {
        var ledger = TranscriptLedger()
        ledger.receive(caption("Later", start: 10, end: 12, final: true))
        ledger.receive(caption(.microphone, "Earlier", start: 3, end: 5, final: true))
        #expect(ledger.context() == "[You] Earlier\n[Meeting] Later")
    }
}
