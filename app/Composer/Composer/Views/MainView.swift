import SwiftUI

struct MainView: View {
    @EnvironmentObject private var app: AppState
    @AppStorage("draftPanelWidth") private var draftPanelWidth: Double = 420

    private var panelVisible: Bool {
        app.isDraftPanelVisible && app.selectedTab != .drafts
    }

    var body: some View {
        VStack(spacing: 0) {
            if app.backendStale {
                staleBanner
            }
            mainSplit
        }
        .onChange(of: app.selectedTab) { _, _ in
            if app.draftsModel.isDirty { app.draftsModel.save() }
        }
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text("Backend is running older code than this app. Restart it to pick up the latest.")
                .font(.callout)
            Spacer()
            Button("Restart Backend") {
                app.supervisor.restart()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.25))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Backend out of date. Restart it to pick up the latest.")
    }

    private var mainSplit: some View {
        HSplitView {
            NavigationStack {
                Group {
                    switch app.selectedTab {
                    case .library:
                        LibraryView(api: app.api)
                    case .collections:
                        CollectionsView(api: app.api)
                    case .notes:
                        NotesView(api: app.api)
                    case .drafts:
                        DraftsView(api: app.api)
                    case .ask:
                        AskView(api: app.api)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Mode", selection: $app.selectedTab) {
                            ForEach(NavTab.allCases) { tab in
                                Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityLabel("Mode")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        HealthBadge(status: app.health)
                    }
                    if app.selectedTab != .drafts && !app.isDraftPanelVisible {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                app.toggleDraftPanel()
                            } label: {
                                Label("Show Draft Panel", systemImage: "sidebar.squares.right")
                            }
                            .help("Show Draft Panel (⌥⌘D)")
                            .accessibilityLabel("Show Draft Panel")
                        }
                    }
                }
            }
            .frame(minWidth: 480)

            if panelVisible {
                DraftSidePanelView(model: app.draftsModel)
                    .frame(minWidth: 320, idealWidth: draftPanelWidth, maxWidth: 800)
                    .background(
                        GeometryReader { geo in
                            Color.clear.onChange(of: geo.size.width) { _, newValue in
                                if newValue > 0 { draftPanelWidth = newValue }
                            }
                        }
                    )
            }
        }
    }
}

#Preview {
    MainView()
        .environmentObject(AppState())
}
