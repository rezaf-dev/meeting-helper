import SwiftUI
import MeetingCore

private let meetingBlue = Color(red: 0.14, green: 0.35, blue: 0.83)

private enum AppBrand {
    static let logo: NSImage = {
        if let url = Bundle.main.url(forResource: "MeetingHelper", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "captions.bubble.fill", accessibilityDescription: "MeetingHelper")!
    }()
}

// Disambiguate the classic property wrapper from the macOS 27 State macro.
// The macro's plugin is not shipped in Command Line Tools.
typealias ViewState<Value> = SwiftUI.State<Value>

struct MeetingView: View {
    @ObservedObject var model: MeetingModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                transcriptPane.frame(minWidth: 360, idealWidth: 460)
                AssistancePane(model: model).frame(minWidth: 440, idealWidth: 640)
            }
            Divider()
            StatusBar(model: model, monitor: model.performance)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(meetingBlue)
        .sheet(isPresented: $model.showHistory) { ChatHistoryView(model: model) }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(settings: model.settings, model: model)
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(nsImage: AppBrand.logo).resizable().interpolation(.high)
                .frame(width: 34, height: 34).accessibilityLabel("MeetingHelper logo")
            VStack(alignment: .leading, spacing: 3) {
                Text("MeetingHelper").font(.system(size: 19, weight: .semibold))
                Text("Listen clearly. Find your words.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.openHistory() } label: { Label("History", systemImage: "clock") }
            Button { model.showFloatingCaptions() } label: {
                Label("Float captions", systemImage: "rectangle.on.rectangle")
            }.help("Keep captions above your meeting window")
            Button { model.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
            }.accessibilityLabel("Settings")
            Button {
                Task { if model.isRunning { await model.stop() } else { await model.start() } }
            } label: {
                HStack(spacing: 7) {
                    if model.isBusy { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.isRunning ? "stop.fill" : "play.fill") }
                    Text(model.isRunning ? "Stop captions" : "Start captions")
                }.frame(minWidth: 122)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isBusy)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            SourceControls(settings: model.settings, disabled: model.isRunning || model.isBusy)
                .padding(.horizontal, 24).padding(.vertical, 14)
            Divider()
            if let error = model.historyError {
                Notice(text: error, symbol: "exclamationmark.triangle", color: .orange)
                    .padding(.horizontal, 20).padding(.top, 12)
            }
            if let error = model.captureError {
                Notice(text: error, symbol: "exclamationmark.triangle", color: .orange)
                    .padding(.horizontal, 20).padding(.top, 12)
            }
            if let warning = model.captureWarning {
                Notice(text: warning, symbol: "exclamationmark.triangle", color: .orange)
                    .padding(.horizontal, 20).padding(.top, 12)
            }
            if model.droppedBuffers > 0 {
                Notice(text: "Audio is falling behind (\(model.droppedBuffers) buffers dropped). Stop and restart with one audio source, or close heavy apps.",
                       symbol: "gauge.with.dots.needle.67percent", color: .orange)
                    .padding(.horizontal, 20).padding(.top, 8)
            }
            if model.isDemo {
                Notice(text: "Example meeting. No microphone or system audio is being captured.",
                       symbol: "play.rectangle", color: meetingBlue)
                    .padding(.horizontal, 20).padding(.top, 12)
            }
            if model.ledger.displayed.isEmpty { emptyTranscript }
            else { CaptionList(model: model, settings: model.settings) }
            Divider()
            HStack {
                Label("Audio processed on this Mac", systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                CopyTextButton(text: model.sessionSnapshot.transcriptText, label: "Copy transcript")
                    .help("Copy the full finalized session transcript")
                Button("Export text") { model.exportTranscript() }
                    .disabled(model.sessionSnapshot.transcriptText.isEmpty)
                    .help("Export the full finalized session transcript")
                Button("New chat") { model.clearSession() }
                    .disabled(model.isRunning || model.isBusy || (model.ledger.displayed.isEmpty && model.assistanceHistory.entries.isEmpty && model.assistance.isEmpty))
                    .help("Save this chat and start a new one")
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyTranscript: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: model.isRunning ? "waveform" : "ear.badge.waveform")
                .font(.system(size: 42, weight: .light)).foregroundStyle(meetingBlue)
            Text(model.isRunning ? "Listening for your next sentence." : "A little more clarity\nfor your next meeting.")
                .font(.system(size: 30, weight: .medium, design: .rounded)).lineSpacing(3)
            Text(model.isRunning
                 ? "Your captions will appear here as you speak or your Mac plays meeting audio."
                 : "Choose your audio sources and start captions. Speech stays on your Mac. Turn on AI assistance when you want help with the conversation.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .lineSpacing(5).frame(maxWidth: 410, alignment: .leading)
            if !model.isRunning && !model.isBusy {
                Button("Try an example meeting") { model.loadDemo() }.buttonStyle(.link)
            }
            Spacer()
            Text("Use headphones when both sources are on to avoid hearing the same speech twice.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(36).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct SourceControls: View {
    @ObservedObject var settings: AppSettings
    let disabled: Bool
    var body: some View {
        HStack(spacing: 18) {
            Toggle(isOn: $settings.microphone) { Label("Microphone", systemImage: "mic") }
            Toggle(isOn: $settings.systemAudio) { Label("Meeting audio", systemImage: "speaker.wave.2") }
            Spacer()
            Text("English").font(.system(size: 12)).foregroundStyle(.secondary)
        }.toggleStyle(.checkbox).disabled(disabled)
    }
}

private struct CaptionList: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var settings: AppSettings
    @ViewState private var followLatest = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Live transcript").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Toggle("Follow latest", isOn: $followLatest).toggleStyle(.checkbox).font(.system(size: 11))
            }.padding(.horizontal, 24).padding(.top, 15)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(Array(model.ledger.displayed.suffix(180))) { caption in
                            CaptionRow(caption: caption, fontSize: settings.fontSize)
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(24)
                }
                .onChange(of: model.ledger.displayed) { _, _ in
                    if followLatest { proxy.scrollTo("latest", anchor: .bottom) }
                }
            }
        }
    }
}

private struct CaptionRow: View {
    let caption: Caption
    let fontSize: Double
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            RoundedRectangle(cornerRadius: 2)
                .fill(caption.source == .system ? meetingBlue.opacity(0.8) : Color.secondary.opacity(0.3))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: caption.source.symbol)
                    Text(caption.source.label).fontWeight(.medium)
                    Text(caption.timestamp.formatted(date: .omitted, time: .shortened)).foregroundStyle(.tertiary)
                    if !caption.isFinal { Text("Listening…").foregroundStyle(meetingBlue) }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                Text(caption.text)
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundStyle(caption.isFinal ? Color.primary : Color.secondary)
                    .lineSpacing(6).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }
}

private struct AssistancePane: View {
    @ObservedObject var model: MeetingModel
    @ViewState private var showNote = true
    private var answerCount: Int {
        model.assistanceHistory.entries.count + (model.assistance.isEmpty ? 0 : 1)
    }

    private struct ResponseRevision: Equatable {
        let text: String
        let error: String?
        let loading: Bool
        let historyCount: Int
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("AI help", systemImage: "text.bubble")
                    .font(.system(size: 14, weight: .semibold))
                Text(answerCount == 1 ? "1 answer" : "\(answerCount) answers")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                CopyTextButton(text: model.sessionSnapshot.answersText, label: "Copy all")
                    .help("Copy all AI answers in this chat, including partial replies")
                Button { model.exportAssistance() } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Save AI answer history")
                    .help("Save all retained AI answers as a text file")
                    .disabled(model.assistanceHistory.entries.isEmpty && model.assistance.isEmpty)
                Button(showNote ? "Hide note" : "Show note") { showNote.toggle() }
                    .font(.system(size: 11))
                    .help("Give the answer more room, or bring back your live note")
                if model.aiIsRunning {
                    Button { model.cancelAI() } label: { Image(systemName: "stop.circle") }
                        .buttonStyle(.plain).help("Cancel AI request")
                }
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            CloudControls(settings: model.settings, model: model).padding(.horizontal, 16)
            Divider().padding(.top, 10)
            FollowingScrollView(revision: ResponseRevision(text: model.assistance, error: model.aiError,
                                                            loading: model.aiIsRunning,
                                                            historyCount: model.assistanceHistory.entries.count)) {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(model.assistanceHistory.entries) { answer in
                        AnswerHistoryRow(answer: answer).equatable()
                        Divider()
                    }
                    if !model.assistance.isEmpty || model.aiIsRunning || model.assistanceHistory.entries.isEmpty {
                        HStack(alignment: .firstTextBaseline) {
                            Text(model.assistanceTitle).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            CopyTextButton(text: model.assistance).controlSize(.small)
                                .help("Copy this AI answer")
                            Text(model.answerDate.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    if model.assistance.isEmpty && !model.aiIsRunning && model.assistanceHistory.entries.isEmpty {
                        Text("Get a simpler explanation, understand a question, or find a natural way to reply.")
                            .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
                    }
                    if model.aiIsRunning && model.assistance.isEmpty {
                        HStack { ProgressView().controlSize(.small); Text("Reading the conversation…").foregroundStyle(.secondary) }
                    }
                    if !model.assistance.isEmpty {
                        Text(model.assistance).font(.system(size: 15)).lineSpacing(6).textSelection(.enabled)
                    }
                    if let error = model.aiError { Notice(text: error, symbol: "exclamationmark.circle", color: .orange) }
                    if let delay = model.firstTextLatency {
                        Text(String(format: "First AI text in %.1f s", delay)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }.id(model.answerTimelineID).frame(minHeight: 180, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button("Explain") { model.analyze(.explain) }.help("Explain what they just said")
                    Button("Their question") { model.analyze(.question) }.help("What did they ask?")
                    Button("Help me reply") { model.analyze(.reply) }.buttonStyle(.borderedProminent)
                    Button("Recap") { model.analyze(.recap) }.help("Catch me up on the conversation")
                    Spacer(minLength: 0)
                }.controlSize(.small)
                if showNote {
                    LiveIntentPad(model: model, settings: model.settings)
                    DisclosureGroup("Meeting context and draft") {
                        VStack(alignment: .leading, spacing: 7) {
                            TextField("Optional wording to polish", text: $model.replyDraft, axis: .vertical)
                                .lineLimit(2...3).textFieldStyle(.roundedBorder)
                            Text("Background facts and agenda. Your live note controls the reply's aim. Sent with AI requests.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            TextEditor(text: $model.notes).font(.system(size: 12)).frame(height: 60)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                            Text("Check AI suggestions for names, dates, and commitments.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(.top, 8)
                    }.font(.system(size: 12))
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}

private struct AnswerHistoryRow: View, Equatable {
    let answer: AssistanceRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(answer.title).font(.system(size: 13, weight: .semibold))
                if answer.status != .complete {
                    Text(answer.status == .partial ? "Partial" : "Incomplete")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                CopyTextButton(text: answer.text).controlSize(.small)
                    .help("Copy this AI answer")
                Text(answer.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .help(answer.date.formatted(date: .abbreviated, time: .standard))
            }
            Text(answer.text).font(.system(size: 15)).lineSpacing(6).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveIntentPad: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var settings: AppSettings

    private var intentBinding: Binding<String> {
        Binding(get: { model.liveIntent }, set: { model.liveIntent = String($0.prefix(3000)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("What I want to say", systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !model.liveIntent.isEmpty {
                    Button("Clear") { model.liveIntent = "" }.font(.system(size: 11))
                }
            }
            ZStack(alignment: .topLeading) {
                if model.liveIntent.isEmpty {
                    Text("need two more days; clarify scope; don't promise Friday")
                        .font(.system(size: 13)).foregroundStyle(.tertiary)
                        .padding(.horizontal, 11).padding(.vertical, 10).allowsHitTesting(false)
                }
                TextEditor(text: intentBinding).font(.system(size: 14))
                    .scrollContentBackground(.hidden).padding(5)
                    .accessibilityLabel("Live intent note")
            }
            .frame(height: 56)
            .background(meetingBlue.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(meetingBlue.opacity(0.3), lineWidth: 1))
            HStack(alignment: .top) {
                Toggle("Update replies as I type", isOn: $settings.followIntent)
                    .toggleStyle(.checkbox).font(.system(size: 11)).disabled(!settings.cloudEnabled)
                Spacer()
                Button("Apply note") { model.analyze(.reply) }.font(.system(size: 11))
                    .disabled(model.liveIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(noteStatus).font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var noteStatus: String {
        if !settings.cloudEnabled { return "Your keywords stay here until AI sharing is enabled." }
        if model.isDemo { return "Example mode. Choose Apply note to request a real AI reply." }
        if model.liveIntent.isEmpty { return "Add keywords, goals, or tone in any language." }
        if model.aiIsRunning { return "Preparing a reply using your latest direction…" }
        if model.appliedIntentRevision == model.intentRevision { return "Latest direction included in the reply." }
        return settings.followIntent ? "Updates after you pause typing. Text is sent through OpenRouter."
            : "Choose Apply note or Help me reply to use this direction."
    }
}

private struct CloudControls: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: MeetingModel
    var body: some View {
        HStack(spacing: 10) {
            Label(settings.cloudEnabled ? "OpenRouter" : "AI is off", systemImage: settings.cloudEnabled ? "network" : "network.slash")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .help("When enabled, meeting text is sent through OpenRouter")
            Toggle("Auto help", isOn: $settings.automaticHelp)
                .toggleStyle(.checkbox).font(.system(size: 11)).disabled(!settings.cloudEnabled)
                .help("Offer new English help after a pause; skip acknowledgments and answered turns")
            Spacer(minLength: 0)
            Button(settings.cloudEnabled ? "Settings" : "Set up") { model.showSettings = true }.font(.system(size: 11))
        }
    }
}

struct Notice: View {
    let text: String
    let symbol: String
    let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.system(size: 12)).lineSpacing(3).textSelection(.enabled)
        }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct StatusBar: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var monitor: PerformanceMonitor
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(model.isRunning ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
            Text(model.status).lineLimit(1)
            Spacer()
            if let delay = model.lastCaptionDelay { Text(String(format: "Caption ~%.1f s", delay)).help("Approximate age of the audio at the end of the latest caption") }
            Text(String(format: "App %.0f MB", monitor.memoryMB))
                .help("App process footprint. Apple's separate speech service uses additional memory.")
            Text(String(format: "CPU %.0f%%", monitor.cpuPercent))
                .help("This app process only; 100% is one CPU core. Excludes Apple's speech service.")
            if monitor.thermal != "Normal" { Text(monitor.thermal).foregroundStyle(.orange) }
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 9)
    }
}

struct FloatingCaptions: View {
    @ObservedObject var model: MeetingModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.isRunning ? "Listening locally" : "Captions", systemImage: "captions.bubble")
                Spacer()
                Button("Hide") { model.hideFloatingCaptions() }.buttonStyle(.plain)
                    .help("Hide this panel. Show it again from MeetingHelper's menu bar icon.")
            }.font(.system(size: 11, weight: .medium))
            Text("Visible on your screen. It may appear in full-display sharing.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .help("For private captions, share a specific app window rather than your entire display.")
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if model.ledger.displayed.isEmpty {
                        Text("Start captions in MeetingHelper.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.ledger.displayed.suffix(3))) { caption in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(caption.source.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Text(caption.text).font(.system(size: 23))
                                .foregroundStyle(caption.isFinal ? Color.primary : Color.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.defaultScrollAnchor(.bottom)
        }.padding(20).background(.regularMaterial)
    }
}
