import SwiftUI

struct SettingsView: View {
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
        .frame(width: 480, height: 280)
        .onAppear { draftKey = app.apiKey }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
