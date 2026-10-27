import SwiftUI
import MeetingCore

struct ChatHistoryView: View {
    @ObservedObject var model: MeetingModel
    @Environment(\.dismiss) private var dismiss
    @ViewState private var selection: UUID?
    @ViewState private var search = ""
    @ViewState private var pendingDelete: SavedChat?

    private var chats: [SavedChat] {
        guard !search.isEmpty else { return model.savedChats }
        return model.savedChats.filter {
            ([$0.title, $0.notes, $0.draft, $0.intent] + $0.captions.map(\.text)
             + $0.answers.map(\.text) + $0.answers.compactMap(\.input)).contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat history").font(.title2.weight(.semibold))
                Spacer()
                Text("Saved on this Mac").foregroundStyle(.secondary)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            if let error = model.historyError {
                HStack {
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { model.openHistory() }
                }.padding(.horizontal, 20).padding(.bottom, 12)
            }
            HSplitView {
                VStack(spacing: 0) {
                    TextField("Search chats", text: $search).textFieldStyle(.roundedBorder).padding(12)
                    if chats.isEmpty {
                        placeholder(search.isEmpty ? "No saved chats" : "No matching chats",
                            detail: search.isEmpty ? "Chats save automatically as you use MeetingHelper."
                                : "Try a different word or clear the search.")
                    } else {
                        List(chats, selection: $selection) { chat in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(chat.title).lineLimit(2).fontWeight(.medium)
                                Text(chat.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(chat.answers.count) \(chat.answers.count == 1 ? "answer" : "answers") · \(chat.captions.count) \(chat.captions.count == 1 ? "caption" : "captions")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6).tag(chat.id)
                        }
                    }
                }.frame(minWidth: 230, idealWidth: 270, maxWidth: 330,
                        maxHeight: .infinity, alignment: .topLeading)
                if let chat = chats.first(where: { $0.id == selection }) {
                    VStack(spacing: 0) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(chat.title).font(.headline)
                                Text("Updated \(chat.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { pendingDelete = chat } label: {
                                Label("Delete chat", systemImage: "trash")
                            }.disabled(chat.id == model.currentChatID && (model.isRunning || model.isBusy))
                                .help("Stop captions before deleting the current chat")
                        }.padding(20)
                        HStack {
                            ChatSharingControls(model: model, chat: chat)
                            Spacer()
                        }.padding(.horizontal, 20).padding(.bottom, 16)
                        Divider()
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                if !chat.intent.isEmpty { section("What I want to say", text: chat.intent) }
                                if !chat.notes.isEmpty { section("Meeting notes", text: chat.notes) }
                                if !chat.draft.isEmpty { section("Draft", text: chat.draft) }
                                if !chat.answers.isEmpty {
                                    Text("AI answers").font(.title3.weight(.semibold))
                                    ForEach(chat.answers) { answer in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(answer.title).font(.headline)
                                                Spacer()
                                                CopyTextButton(text: answer.text).controlSize(.small)
                                                    .help("Copy this AI answer")
                                            }
                                            Text("\(answer.date.formatted(date: .omitted, time: .shortened)) · \(answer.model) · \(answer.status.rawValue)")
                                                .font(.caption).foregroundStyle(.secondary)
                                            if let input = answer.input {
                                                DisclosureGroup("Request context") { Text(input).padding(.top, 8) }
                                            }
                                            Text(answer.text).lineSpacing(4)
                                        }
                                        Divider()
                                    }
                                }
                                if !chat.captions.isEmpty {
                                    Text("Transcript").font(.title3.weight(.semibold))
                                    ForEach(chat.captions) { caption in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text("\(caption.source.label) · \(caption.timestamp.formatted(date: .omitted, time: .standard))")
                                                .font(.caption).foregroundStyle(.secondary)
                                            Text(caption.text)
                                        }
                                    }
                                }
                            }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        }.id(chat.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }.frame(minWidth: 420, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    placeholder("Choose a chat", detail: "Read past transcripts, requests, and AI answers here.")
                }
            }
            // The split view must fill the sheet even when neither pane has a scrollable list.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 900, height: 650, alignment: .topLeading)
        .onAppear { selection = model.savedChats.first?.id }
        .alert("Delete this chat?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete chat", role: .destructive) {
                if let chat = pendingDelete { model.deleteChat(chat.id) }
                pendingDelete = nil
            }
        } message: { Text("This permanently removes its transcript, AI answers, and notes from this Mac.") }
    }

    private func placeholder(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "text.bubble").font(.title2).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(text)
        }
    }
}
