import SwiftUI

/// Local-only UI fixture. Build with the production sources except MeetingHelperApp.swift
/// and a separate bundle identifier. No recorder or AI request is started.
@main
struct MeetingUIProbe: App {
    @StateObject private var model = MeetingModel()
    @ViewState private var paragraph = 30

    var body: some Scene {
        WindowGroup("MeetingHelper UI check") {
            VStack(spacing: 0) {
                HStack {
                    Text("Local UI fixture · no capture or AI requests")
                    Button("Append answer") { append() }
                    Button("New answer") {
                        model.archiveAssistance()
                        paragraph = 5
                        model.assistance = (1...paragraph).map(line).joined(separator: "\n\n")
                    }
                    Button("Stream answer") {
                        Task { @MainActor in
                            for _ in 0..<20 {
                                try? await Task.sleep(for: .milliseconds(150))
                                append()
                            }
                        }
                    }
                }.padding(8)
                Divider()
                MeetingView(model: model)
            }
            .frame(minWidth: 980, minHeight: 760)
            .onAppear {
                model.loadDemo()
                model.assistanceTitle = "Meeting reply"
                model.assistance = (1...paragraph).map(line).joined(separator: "\n\n")
            }
        }.defaultSize(width: 1180, height: 860)
    }

    private func line(_ number: Int) -> String {
        "Point \(number). I can share an initial estimate after checking the integration scope. Let's confirm the requirements before committing to a delivery date."
    }

    private func append() {
        paragraph += 1
        model.assistance += "\n\n" + line(paragraph)
    }
}
