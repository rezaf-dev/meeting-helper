import AppKit
import Combine
import MeetingCore

@MainActor
final class MeetingModel: ObservableObject {
    let settings = AppSettings()
    let performance = PerformanceMonitor()
    @Published var ledger = TranscriptLedger()
    @Published var isRunning = false
    @Published var isBusy = false
    @Published var status = "Ready when you are"
    @Published var captureError: String?
    @Published var captureWarning: String?
    @Published var droppedBuffers = 0
    @Published var notes = ""
    @Published var replyDraft = ""
    @Published var liveIntent = "" { didSet { intentChanged() } }
    @Published private(set) var intentRevision = 0
    @Published private(set) var appliedIntentRevision = -1
    @Published var assistance = ""
    @Published private(set) var assistanceHistory = AssistanceHistory()
    @Published private(set) var answerTimelineID = UUID()
    @Published private(set) var answerDate = Date()
    private var answerID = UUID()
    private var answerModel = ""
    private var answerInput: String?
    private var answerInterrupted = false
    private var answerFailed = false
    @Published var assistanceTitle = "Meeting assistance"
    @Published var aiError: String?
    @Published var aiIsRunning = false
    @Published var firstTextLatency: Double?
    @Published var lastCaptionDelay: Double?
    @Published var isDemo = false
    @Published var showSettings = false
    @Published var floatingIsVisible = false
    @Published var cloudContext = ""
    private let capture = AudioCapture()
    private lazy var floatingController = FloatingCaptionController(model: self)
    private var pipelines: [LocalSpeech] = []
    private var aiTask: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?
    private var intentTask: Task<Void, Never>?
    private var lastAutomaticRequest = Date.distantPast
    private var lastManualRequest = Date.distantPast
    private var requestID = UUID()
    private var captureID = UUID()
    private var automaticPolicy = AutomaticHelpPolicy()
    private var lastCaptionActivity = Date.distantPast
    private var finalVersion = 0
    private var analyzedVersion = 0
    private var automaticFailure = false
    private var activeAction: AssistanceAction?
    private var cancellables: Set<AnyCancellable> = []
    @Published var showHistory = false
    @Published private(set) var savedChats: [SavedChat] = []
    @Published private(set) var historyError: String?
    private var chat = SavedChat()
    private var saveTask: Task<Void, Never>?
    private var restoringChat = false
    private let chatStore: ChatStore

    var currentChatID: UUID { chat.id }

    func refreshHistory() {
        do {
            let report = try chatStore.loadReport()
            savedChats = report.chats
            historyError = report.unreadableFiles.isEmpty ? nil
                : "Some chats could not be read. Their files were left untouched: " + report.unreadableFiles.joined(separator: ", ")
        }
        catch { historyError = error.localizedDescription }
    }

    /// Includes archived captions beyond the bounded live ledger, plus unsaved current text.
    var sessionSnapshot: SavedChat {
        var snapshot = chat
        snapshot.notes = notes; snapshot.draft = replyDraft; snapshot.intent = liveIntent
        var history = assistanceHistory
        history.retain(currentAnswerRecord)
        snapshot.answers = history.entries
        var captions = Dictionary(uniqueKeysWithValues: chat.captions.map { ($0.id, $0) })
        for caption in ledger.finalized { captions[caption.id] = caption }
        snapshot.captions = captions.values.sorted { $0.timestamp < $1.timestamp }
        return snapshot
    }

    @discardableResult
    func saveChat() -> Bool {
        guard !restoringChat, !isDemo else { return true }
        var snapshot = sessionSnapshot
        guard !snapshot.isEmpty || !chat.isEmpty else { return true }
        snapshot.updatedAt = Date()
        do {
            try chatStore.save(snapshot)
            chat = snapshot
            // Refresh the list only when it is being read, avoiding churn during streaming.
            historyError = nil
            if showHistory { refreshHistory() }
            return true
        } catch {
            historyError = "Could not save chat: \(error.localizedDescription)"
            return false
        }
    }

    func openHistory() {
        if saveChat() { refreshHistory() }
        showHistory = true
    }

    func deleteChat(_ id: UUID) {
        guard id != chat.id || (!isRunning && !isBusy) else { return }
        do {
            try chatStore.delete(id: id)
            if id == chat.id {
                // Reset without saving: a deleted chat must never be resurrected by autosave.
                resetSession()
            }
            refreshHistory()
        } catch { historyError = "Could not delete chat: \(error.localizedDescription)" }
    }

    private func scheduleSave() {
        guard saveTask == nil, !restoringChat else { return }
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self else { return }
            self.saveTask = nil
            self.saveChat()
        }
    }

    private func restoreLatestChat() {
        refreshHistory()
        guard let latest = savedChats.first else { return }
        restoringChat = true
        chat = latest
        for caption in latest.captions { ledger.receive(caption) }
        for answer in latest.answers { assistanceHistory.retain(answer) }
        notes = latest.notes; replyDraft = latest.draft; liveIntent = latest.intent
        intentTask?.cancel(); intentTask = nil
        status = "Saved chat restored"
        restoringChat = false
    }

    init(chatDirectory: URL? = nil) {
        chatStore = ChatStore(directory: chatDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("MeetingHelper/Chats", isDirectory: true))
        restoreLatestChat()
        Publishers.MergeMany([
            $ledger.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $assistance.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $assistanceHistory.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $notes.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $replyDraft.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $liveIntent.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]).sink { [weak self] in self?.scheduleSave() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.saveChat() }.store(in: &cancellables)
        performance.start()
        settings.$cloudEnabled.dropFirst().sink { [weak self] enabled in
            if enabled { self?.automaticFailure = false }
            else { self?.cancelAI() }
        }.store(in: &cancellables)
        settings.$automaticHelp.dropFirst().sink { [weak self] enabled in
            if !enabled {
                self?.automaticTask?.cancel()
                self?.automaticTask = nil
                if self?.activeAction == .live { self?.cancelAI() }
            } else { self?.automaticFailure = false }
        }.store(in: &cancellables)
        settings.$followIntent.dropFirst().sink { [weak self] enabled in
            if !enabled { self?.intentTask?.cancel(); self?.intentTask = nil }
        }.store(in: &cancellables)
        settings.$englishLevel.dropFirst().sink { [weak self] _ in self?.cancelAI() }.store(in: &cancellables)
        settings.$speakingStyle.dropFirst().sink { [weak self] _ in self?.cancelAI() }.store(in: &cancellables)
        settings.$answerLength.dropFirst().sink { [weak self] _ in self?.cancelAI() }.store(in: &cancellables)
        settings.$importantOnly.dropFirst().sink { [weak self] _ in self?.cancelAI() }.store(in: &cancellables)
        settings.$profileNote.dropFirst().sink { [weak self] _ in self?.cancelAI() }.store(in: &cancellables)
        settings.$includeProfile.dropFirst().sink { [weak self] _ in self?.cancelAI() }.store(in: &cancellables)
        settings.$requestCaptureExclusion.dropFirst().sink { [weak self] requested in
            self?.floatingController.setCaptureExclusion(requested)
        }.store(in: &cancellables)
    }

    func showFloatingCaptions() { floatingController.show() }
    func hideFloatingCaptions() { floatingController.hide() }
    func toggleFloatingCaptions() {
        if floatingIsVisible { hideFloatingCaptions() }
        else { showFloatingCaptions() }
    }

    func start() async {
        guard !isBusy, !isRunning else { return }
        guard settings.microphone || settings.systemAudio else {
            captureError = "Select Microphone, Meeting audio, or both before starting."
            return
        }
        if isDemo { resetSession() }
        cancelAI()
        // A fresh timeline prevents range collisions with the previous recording.
        ledger = TranscriptLedger()
        automaticPolicy = AutomaticHelpPolicy()
        lastCaptionActivity = .distantPast
        finalVersion = 0
        analyzedVersion = 0
        automaticFailure = false
        lastManualRequest = .distantPast
        cloudContext = ""
        archiveAssistance()
        aiError = nil
        firstTextLatency = nil
        lastCaptionDelay = nil
        cancelAI()
        captureID = UUID()
        let sessionID = captureID
        isBusy = true
        captureError = nil
        captureWarning = nil
        droppedBuffers = 0
        status = "Preparing on-device speech…"
        defer { isBusy = false }
        do {
            var failures: [String] = []
            var activeSources: [AudioSource] = []
            for source in AudioSource.allCases where (source == .microphone ? settings.microphone : settings.systemAudio) {
                let pipeline = LocalSpeech(source: source)
                do {
                    let callback = try await pipeline.start(
                        localeID: settings.locale, vocabulary: settings.vocabularyTerms,
                        fasterResults: settings.fasterCaptions,
                        status: { [weak self] in self?.status = $0 },
                        result: { [weak self] caption in
                            guard let self, self.captureID == sessionID else { return }
                            self.receive(caption)
                        },
                        failure: { [weak self] message in self?.captureFailed(message, sessionID: sessionID) },
                        overflow: { [weak self] in
                            guard let self, self.captureID == sessionID else { return }
                            self.droppedBuffers += 1
                        })
                    if source == .microphone {
                        status = "Connecting to your microphone…"
                        try await capture.startMicrophone(receive: callback) { [weak self] message in
                            self?.captureFailed(message, sessionID: sessionID)
                        }
                    } else {
                        status = "Connecting to meeting audio…"
                        try await capture.startSystemAudio(receive: callback)
                    }
                    pipelines.append(pipeline)
                    activeSources.append(source)
                } catch {
                    await pipeline.cancel()
                    failures.append(error.localizedDescription)
                }
            }
            guard !activeSources.isEmpty else {
                throw MeetingError.message(failures.joined(separator: "\n\n"))
            }
            captureWarning = failures.isEmpty ? nil : failures.joined(separator: "\n\n")
            if let captureError { throw MeetingError.message(captureError) }
            isRunning = true
            status = activeSources.count == 2 ? "Listening locally · microphone + meeting audio"
                : (activeSources.first == .microphone ? "Listening locally · microphone only" : "Listening locally · meeting audio only")
        } catch {
            await capture.stop()
            for pipeline in pipelines { await pipeline.cancel() }
            pipelines.removeAll()
            captureError = error.localizedDescription
            status = "Could not start captions"
        }
    }

    func stop() async {
        guard !isBusy else { return }
        isBusy = true
        isRunning = false
        status = "Finishing captions…"
        cancelAI()
        await capture.stop()
        for pipeline in pipelines { await pipeline.stop() }
        pipelines.removeAll()
        ledger.clearPartials()
        automaticTask?.cancel()
        automaticTask = nil
        status = "Session stopped"
        isBusy = false
    }

    private func captureFailed(_ message: String, sessionID: UUID) {
        guard captureID == sessionID else { return }
        captureError = message
        // During setup, errors are handled by start(). Runtime failures stop both inputs.
        if isRunning { Task { await stop() } }
    }

    private func receive(_ caption: Caption) {
        let previousDisplay = ledger.displayed
        let previousFinals = ledger.finalized
        ledger.receive(caption)
        if caption.isFinal, let finalized = ledger.finalized.first(where: {
            $0.source == caption.source && abs($0.start - caption.start) < 0.001
        }) {
            if let index = chat.captions.firstIndex(where: { $0.id == finalized.id }) {
                chat.captions[index] = finalized
            } else { chat.captions.append(finalized) }
        }
        let lastAudioTime = caption.timestamp.addingTimeInterval(max(0, caption.end - caption.start))
        lastCaptionDelay = max(0, Date().timeIntervalSince(lastAudioTime))
        if ledger.finalized != previousFinals { finalVersion += 1 }
        guard ledger.displayed != previousDisplay else { return }
        lastCaptionActivity = Date()
        automaticTask?.cancel()
        automaticTask = nil
        // Never publish help for an older turn after the conversation resumes.
        if activeAction == .live { cancelAI() }
        scheduleAutomaticHelp()
    }

    private func scheduleAutomaticHelp() {
        guard settings.cloudEnabled, settings.automaticHelp, !isDemo, !automaticFailure,
              isRunning, automaticTask == nil, intentTask == nil else { return }
        // Both provisional and final changes restart the quiet window. Apple
        // finalization is not itself evidence that the speaker has finished.
        let delay = max(0.1, AutomaticHelpPolicy.quietInterval - Date().timeIntervalSince(lastCaptionActivity),
                        2 - Date().timeIntervalSince(lastAutomaticRequest),
                        12 - Date().timeIntervalSince(lastManualRequest))
        automaticTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            self.automaticTask = nil
            guard self.isRunning, self.settings.cloudEnabled, self.settings.automaticHelp,
                  self.finalVersion > self.analyzedVersion else { return }
            if self.aiIsRunning { return }
            // Do not analyze the old finalized question while a newer turn is
            // still provisional. Its final update will schedule another check.
            guard AutomaticHelpPolicy.isSettled(self.ledger, lastActivity: self.lastCaptionActivity) else { return }
            guard self.automaticPolicy.newContext(in: self.ledger.finalized) != nil else {
                self.automaticPolicy.markHandled(self.ledger.finalized)
                self.analyzedVersion = self.finalVersion
                return
            }
            self.analyze(.live)
        }
    }

    private func intentChanged() {
        intentRevision += 1
        intentTask?.cancel()
        intentTask = nil
        automaticTask?.cancel()
        automaticTask = nil
        // A reply based on an older aim must never arrive after the user changes direction.
        if aiIsRunning { cancelAI() }
        guard !restoringChat, settings.cloudEnabled, settings.followIntent, !isDemo, !isBusy,
              !liveIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let revision = intentRevision
        intentTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            guard let self, self.intentRevision == revision, self.settings.cloudEnabled,
                  self.settings.followIntent else { return }
            self.intentTask = nil
            self.analyze(.reply)
        }
    }

    func analyze(_ action: AssistanceAction) {
        if action != .live { automaticFailure = false }
        guard settings.cloudEnabled else { showSettings = true; return }
        guard let key = CredentialStore.read(), !key.isEmpty else {
            settings.hasAPIKey = false
            automaticFailure = true
            showSettings = true
            aiError = "Add your OpenRouter API key in Settings. Local captions work without it."
            return
        }
        settings.hasAPIKey = true
        let transcript = ledger.context()
        let canUseIntentAlone = (action == .reply || action == .live)
            && !liveIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !transcript.isEmpty || canUseIntentAlone else {
            aiError = "Wait for a completed caption, or add what you want to say and choose Help me reply."
            return
        }
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { aiError = "Choose an AI model in Settings."; return }
        automaticTask?.cancel()
        automaticTask = nil
        intentTask?.cancel()
        intentTask = nil
        aiTask?.cancel()
        requestID = UUID()
        let id = requestID
        let version = finalVersion
        let captions = ledger.finalized
        let newTranscript = automaticPolicy.newContext(in: captions) ?? ""
        let previousAssistance = assistance
        if action != .live {
            archiveAssistance()
            answerID = id
            answerDate = Date()
            answerModel = model
            answerInterrupted = false
            answerFailed = false
            assistanceTitle = action.label
        }
        if action != .live { lastManualRequest = Date() }
        aiError = nil
        firstTextLatency = nil
        aiIsRunning = true
        activeAction = action
        lastAutomaticRequest = Date()
        let start = Date()
        let currentNotes = notes
        let currentMemory = cloudContext
        let draft = replyDraft
        let currentIntent = liveIntent
        let input = "What I want to say: \(currentIntent)\n\nMeeting notes: \(currentNotes)\n\nDraft: \(draft)\n\nTranscript sent:\n\(transcript)"
        if action != .live { answerInput = input }
        saveChat()
        let intentVersion = intentRevision
        let profile = settings.includeProfile ? settings.profileNote : ""
        let aiSessionID = captureID.uuidString
        let preferences = settings.helpPreferences
        aiTask = Task { [weak self] in
            var buffered = ""
            do {
                try await AIClient().analyze(key: key, model: model, action: action, transcript: transcript,
                                             notes: currentNotes, memory: currentMemory, draft: draft,
                                             intent: currentIntent, profile: profile,
                                             sessionID: aiSessionID, preferences: preferences,
                                             newTranscript: newTranscript, previousAssistance: previousAssistance) { [weak self] delta in
                    guard let self, self.requestID == id else { return }
                    if self.firstTextLatency == nil {
                        self.firstTextLatency = Date().timeIntervalSince(start)
                        if action != .live { self.assistance = "" }
                    }
                    if action == .live { buffered += delta }
                    else { self.assistance += delta }
                }
                guard let self, self.requestID == id else { return }
                if action == .live, let text = LiveHelpResult.usefulText(buffered, previous: previousAssistance) {
                    self.archiveAssistance()
                    self.answerID = id
                    self.answerDate = start
                    self.answerModel = model
                    self.answerInput = input
                    self.assistanceTitle = action.label
                    self.assistance = text
                }
                self.automaticPolicy.markHandled(captions)
                self.analyzedVersion = version
                self.appliedIntentRevision = intentVersion
                if action == .recap { self.cloudContext = String(self.assistance.prefix(4000)) }
                self.aiIsRunning = false
                self.activeAction = nil
                self.aiTask = nil
                self.saveChat()
                if self.finalVersion > version { self.scheduleAutomaticHelp() }
            } catch {
                guard let self, self.requestID == id else { return }
                self.aiIsRunning = false
                self.activeAction = nil
                self.aiTask = nil
                if !Task.isCancelled {
                    if action != .live { self.answerFailed = true }
                    self.aiError = error.localizedDescription
                    if action == .live {
                        self.automaticFailure = true
                        self.aiError = error.localizedDescription + " Automatic help is paused. Use a help button to retry."
                    }
                    // Do not repeatedly bill/retry a failed automatic request.
                    self.automaticTask?.cancel()
                    self.automaticTask = nil
                }
                self.saveChat()
            }
        }
    }

    func cancelAI() {
        if aiIsRunning && activeAction != .live { answerInterrupted = true }
        requestID = UUID()
        aiTask?.cancel()
        aiTask = nil
        automaticTask?.cancel()
        automaticTask = nil
        intentTask?.cancel()
        intentTask = nil
        aiIsRunning = false
        activeAction = nil
        saveChat()
    }

    func clearSession() {
        guard !isRunning, !isBusy else { return }
        cancelAI()
        guard saveChat() else { return }
        resetSession()
    }

    private func resetSession() {
        restoringChat = true
        defer { restoringChat = false }
        endDemo()
        cancelAI()
        saveTask?.cancel(); saveTask = nil
        chat = SavedChat()
        ledger = TranscriptLedger()
        assistance = ""
        assistanceHistory.clear()
        answerID = UUID()
        answerDate = Date()
        answerModel = ""
        answerInput = nil
        answerInterrupted = false
        answerFailed = false
        answerTimelineID = UUID()
        aiError = nil
        cloudContext = ""
        notes = ""
        replyDraft = ""
        liveIntent = ""
        appliedIntentRevision = -1
        automaticPolicy = AutomaticHelpPolicy()
        lastCaptionActivity = .distantPast
        finalVersion = 0
        analyzedVersion = 0
        firstTextLatency = nil
        lastCaptionDelay = nil
        status = "Ready when you are"
    }

    private var currentAnswerRecord: AssistanceRecord {
        AssistanceRecord(id: answerID, title: assistanceTitle, text: assistance,
                         date: answerDate, model: answerModel,
                         status: answerFailed ? .failed : ((answerInterrupted || (aiIsRunning && activeAction != .live)) ? .partial : .complete),
                         input: answerInput)
    }

    func archiveAssistance() {
        assistanceHistory.retain(currentAnswerRecord)
        assistance = ""
        answerID = UUID()
        answerDate = Date()
        answerInput = nil
        answerInterrupted = false
        answerFailed = false
    }

    func exportAssistance() { exportText(.answers) }

    func exportTranscript() { exportText(.transcript) }

    func exportText(_ kind: ChatTextKind, chat saved: SavedChat? = nil) {
        let snapshot = saved.map { $0.id == currentChatID ? sessionSnapshot : $0 } ?? sessionSnapshot
        let text = snapshot.text(for: kind)
        guard !text.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let day = snapshot.createdAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        panel.nameFieldStringValue = "Meeting \(day) \(kind.fileSuffix).txt"
        panel.message = kind == .transcript
            ? "Save the full finalized transcript, including captions no longer shown in the live view."
            : "Save \(kind.label.lowercased()) as a UTF-8 text file."
        if panel.runModal() == .OK, let url = panel.url {
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { historyError = "Could not export \(kind.label.lowercased()): \(error.localizedDescription)" }
        }
    }

    func loadDemo() {
        guard !isRunning, !isBusy else { return }
        clearSession()
        guard chat.isEmpty else { return }
        isDemo = true
        status = "Demo — no audio is being captured"
        let epoch = Date().addingTimeInterval(-15)
        let lines: [(AudioSource, String)] = [
            (.system, "Before we wrap up, can you give us a ballpark estimate for the integration?"),
            (.microphone, "I need to check the authentication changes first."),
            (.system, "That makes sense. Let's touch base tomorrow and flag any blockers early.")
        ]
        for (index, line) in lines.enumerated() {
            ledger.receive(Caption(source: line.0, text: line.1, start: Double(index * 4),
                                   end: Double(index * 4 + 3), timestamp: epoch.addingTimeInterval(Double(index * 4)), isFinal: true))
        }
        finalVersion = lines.count
        answerID = UUID()
        answerDate = Date()
        answerModel = "Example (local)"
        answerInterrupted = false
        assistanceTitle = "Example explanation"
        assistance = "“Ballpark estimate” means an approximate estimate. “Touch base” means have a short follow-up conversation. A “blocker” is a problem that prevents progress.\n\nThey want an initial estimate and a follow-up tomorrow. You have not committed to a delivery date."
    }

    private func endDemo() { isDemo = false }
}
