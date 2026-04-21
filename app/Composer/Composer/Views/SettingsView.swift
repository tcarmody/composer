import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var draftKey: String = ""
    @State private var reindexState: ReindexState = .idle

    enum ReindexState: Equatable {
        case idle
        case running
        case done(counts: [String: Int], at: Date)
        case error(String)
    }

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
        .frame(width: 480, height: 380)
        .onAppear { draftKey = app.apiKey }
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

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
