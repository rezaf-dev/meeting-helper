import SwiftUI
import MeetingCore

struct ModelPickerView: View {
    @ObservedObject var settings: AppSettings
    @ViewState private var models: [OpenRouterModel] = OpenRouterModel.presets
    @ViewState private var search = ""
    @ViewState private var loading = false
    @ViewState private var error: String?
    @ViewState private var showBrowser = false

    private var matches: [OpenRouterModel] {
        models.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
            || $0.id.localizedCaseInsensitiveContains(search) }
    }

    private var selectedPreset: OpenRouterModel? {
        OpenRouterModel.presets.first { $0.id == settings.model }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Quick picks", selection: $settings.model) {
                ForEach(OpenRouterModel.presets) { item in
                    Text(item.name + (item.id == OpenRouterModel.defaultID ? " (default)" : ""))
                        .tag(item.id)
                }
                if selectedPreset == nil {
                    Text("Custom / browsed model").tag(settings.model)
                }
            }
            if let preset = selectedPreset, let guidance = preset.guidance {
                Text(guidance).font(.system(size: 11)).foregroundStyle(.secondary)
                Link("Model details & pricing", destination: URL(string: "https://openrouter.ai/\(preset.id)")!)
                    .font(.system(size: 11))
            }
            TextField("OpenRouter model ID", text: $settings.model)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("Speed, availability, and cost vary by model and provider.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Use default") { settings.model = OpenRouterModel.defaultID }.font(.system(size: 11))
            }
            Button(showBrowser ? "Hide model browser" : "Browse OpenRouter models") {
                showBrowser.toggle()
            }.buttonStyle(.link).font(.system(size: 12))
            if showBrowser {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Search model or provider", text: $search).textFieldStyle(.roundedBorder)
                        Button(loading ? "Loading…" : "Load models") { Task { await load() } }.disabled(loading)
                    }
                    if let error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(matches.prefix(40))) { item in
                                Button {
                                    settings.model = item.id
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name).font(.system(size: 12, weight: .medium))
                                            Text(item.id).font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if settings.model == item.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                    }.padding(7).frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(height: 150)
                    Text("\(matches.count) text models match. Showing up to 40; search to narrow. Availability and pricing vary by model.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
        }
    }

    @MainActor private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do { models = try await OpenRouterModel.fetch() }
        catch { self.error = error.localizedDescription }
    }
}
