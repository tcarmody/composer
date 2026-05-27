import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @AppStorage("settingsSelectedTab") private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, Hashable {
        case general, ai, appearance, editor
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            AISettingsPane()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(SettingsTab.ai)

            AppearanceSettingsPane()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)

            EditorSettingsPane()
                .tabItem { Label("Editor", systemImage: "square.and.pencil") }
                .tag(SettingsTab.editor)
        }
        .frame(width: 520, height: 540)
        .environmentObject(app)
    }
}

// MARK: - General (Backend + API Key)

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var app: AppState
    @State private var draftKey: String = ""

    var body: some View {
        Form {
            Section("Backend") {
                LabeledContent("Base URL") {
                    Text(app.api.baseURL.absoluteString)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Status") {
                    HealthBadge(status: app.health)
                }
                LabeledContent("Process") {
                    Text(app.supervisor.status.shortLabel)
                        .foregroundStyle(processStatusColor)
                }
                LabeledContent("Project root") {
                    Text(app.supervisor.projectRootPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Start") {
                        Task { await app.supervisor.start() }
                    }
                    .disabled(!canStart)
                    Button("Stop") {
                        app.supervisor.stop()
                    }
                    .disabled(!canStop)
                    Button("Restart") {
                        app.supervisor.restart()
                    }
                    .disabled(app.supervisor.status == .starting)
                }
                if case .failed(let msg) = app.supervisor.status {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !app.supervisor.recentLog.isEmpty {
                    ScrollView {
                        Text(app.supervisor.recentLog)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(height: 120)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)
                }
            }

            Section("API Key") {
                SecureField("X-API-Key (leave blank if auth is disabled)", text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") {
                        app.setAPIKey(draftKey)
                        Task { await app.refreshHealth() }
                    }
                    .disabled(draftKey == app.apiKey)
                    Button("Clear") {
                        draftKey = ""
                        app.setAPIKey("")
                        Task { await app.refreshHealth() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { draftKey = app.apiKey }
    }

    private var canStart: Bool {
        switch app.supervisor.status {
        case .stopped, .failed: return true
        default: return false
        }
    }

    private var canStop: Bool {
        if case .running = app.supervisor.status { return true }
        return false
    }

    private var processStatusColor: Color {
        switch app.supervisor.status {
        case .running: return .green
        case .externallyManaged: return .blue
        case .starting: return .secondary
        case .stopped: return .secondary
        case .failed: return .red
        }
    }
}

// MARK: - AI (LLM Keys + Index)

private struct AISettingsPane: View {
    @EnvironmentObject private var app: AppState
    @State private var reindexState: ReindexState = .idle
    @State private var llmKeys: [String: LLMKeyStatus] = [:]
    @State private var keyDrafts: [String: String] = [:]
    @State private var llmKeysWorking: Bool = false
    @State private var llmKeysError: String?

    private struct LLMKeyDef {
        let name: String
        let label: String
        let placeholder: String
        let description: String
    }

    private let llmKeyDefs: [LLMKeyDef] = [
        .init(
            name: "anthropic",
            label: "Anthropic",
            placeholder: "sk-ant-…",
            description: "Powers draft Assist, item summaries, and Ask chat."
        ),
        .init(
            name: "openai",
            label: "OpenAI",
            placeholder: "sk-…",
            description: "Optional. Reserved for OpenAI-backed features."
        ),
        .init(
            name: "voyage",
            label: "Voyage",
            placeholder: "pa-…",
            description: "Powers vector search embeddings."
        ),
    ]

    enum ReindexState: Equatable {
        case idle
        case running
        case done(counts: [String: Int], at: Date)
        case error(String)
    }

    var body: some View {
        Form {
            Section("LLM Keys") {
                ForEach(llmKeyDefs, id: \.name) { def in
                    llmKeyRow(def)
                }
                if let err = llmKeysError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Stored on the backend at data/secrets.json with mode 0600. UI-set keys override the corresponding environment variables.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Index") {
                HStack {
                    Button {
                        runReindex()
                    } label: {
                        if case .running = reindexState {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Rebuilding…")
                            }
                        } else {
                            Text("Rebuild search index")
                        }
                    }
                    .disabled(reindexState == .running)
                    Spacer()
                }
                reindexStatusView
            }
        }
        .formStyle(.grouped)
        .onAppear { loadLLMKeys() }
    }

    @ViewBuilder
    private func llmKeyRow(_ def: LLMKeyDef) -> some View {
        let status = llmKeys[def.name]
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.label).font(.subheadline).bold()
                    Text(def.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(statusLabel(for: status))
                    .font(.caption)
                    .foregroundStyle(statusColor(for: status))
            }
            SecureField(def.placeholder, text: draftBinding(for: def.name))
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save") { saveKey(def.name) }
                    .disabled(
                        (keyDrafts[def.name] ?? "").isEmpty || llmKeysWorking
                    )
                if status?.source == "file" {
                    Button("Clear", role: .destructive) { clearKey(def.name) }
                        .disabled(llmKeysWorking)
                }
                if llmKeysWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func draftBinding(for name: String) -> Binding<String> {
        Binding(
            get: { keyDrafts[name] ?? "" },
            set: { keyDrafts[name] = $0 }
        )
    }

    private func statusLabel(for status: LLMKeyStatus?) -> String {
        guard let status else { return "Loading…" }
        if !status.isSet { return "Not configured" }
        switch status.source {
        case "file": return "Set via UI"
        case "env": return "Set via environment"
        default: return "Set"
        }
    }

    private func statusColor(for status: LLMKeyStatus?) -> Color {
        guard let status else { return .secondary }
        return status.isSet ? .green : .orange
    }

    private func loadLLMKeys() {
        Task {
            do {
                let keys = try await app.api.getLLMKeys()
                llmKeys = keys
                llmKeysError = nil
            } catch {
                llmKeysError = error.localizedDescription
            }
        }
    }

    private func saveKey(_ name: String) {
        let value = keyDrafts[name] ?? ""
        guard !value.isEmpty else { return }
        llmKeysWorking = true
        llmKeysError = nil
        Task {
            defer { llmKeysWorking = false }
            do {
                let keys = try await app.api.setLLMKey(name, value: value)
                llmKeys = keys
                keyDrafts[name] = ""
            } catch {
                llmKeysError = error.localizedDescription
            }
        }
    }

    private func clearKey(_ name: String) {
        llmKeysWorking = true
        llmKeysError = nil
        Task {
            defer { llmKeysWorking = false }
            do {
                let keys = try await app.api.clearLLMKey(name)
                llmKeys = keys
            } catch {
                llmKeysError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var reindexStatusView: some View {
        switch reindexState {
        case .idle:
            Text("Re-chunks and re-embeds every item, note, and draft. Useful after changing embedding settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .running:
            Text("This may take a minute for large archives.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .done(let counts, let at):
            VStack(alignment: .leading, spacing: 2) {
                Text(summary(counts))
                    .font(.caption)
                Text("Last run \(at, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func summary(_ counts: [String: Int]) -> String {
        let items = counts["item", default: 0]
        let notes = counts["note", default: 0]
        let drafts = counts["draft", default: 0]
        return "Indexed \(items) item chunks, \(notes) note chunks, \(drafts) draft chunks."
    }

    private func runReindex() {
        reindexState = .running
        Task {
            do {
                let counts = try await app.api.reindex()
                reindexState = .done(counts: counts, at: Date())
            } catch {
                reindexState = .error(error.localizedDescription)
            }
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettingsPane: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $app.theme) {
                    ForEach(AppTheme.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                Text(app.theme.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("List") {
                Picker("Density", selection: $app.listDensity) {
                    ForEach(ListDensity.allCases) { d in
                        Text(d.label).tag(d)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Type") {
                Picker("Typeface", selection: $app.typeface) {
                    ForEach(AppTypeface.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Editor

private struct EditorSettingsPane: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            Section("Smart Quotes") {
                Toggle("Convert straight quotes automatically", isOn: $app.smartQuotesAutoConvert)
                Text("When a note, story, or other document is sent to a draft, straight quotes (\") are converted to curly quotes (\u{201C}\u{201D}).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
