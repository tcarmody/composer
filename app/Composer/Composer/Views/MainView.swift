import SwiftUI

struct MainView: View {
    @EnvironmentObject private var app: AppState

    private var panelVisible: Bool {
        app.isDraftPanelVisible && app.selectedTab != .drafts
    }

    var body: some View {
        HStack(spacing: 0) {
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
                    ToolbarItem(placement: .navigation) {
                        Picker("Tab", selection: $app.selectedTab) {
                            ForEach(NavTab.allCases) { tab in
                                Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        HealthBadge(status: app.health)
                    }
                    if app.selectedTab != .drafts {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                app.toggleDraftPanel()
                            } label: {
                                Image(systemName: app.isDraftPanelVisible ? "sidebar.right" : "sidebar.squares.right")
                            }
                            .help(app.isDraftPanelVisible ? "Hide Draft Panel (⌥⌘D)" : "Show Draft Panel (⌥⌘D)")
                        }
                    }
                }
            }

            if panelVisible {
                Divider()
                DraftSidePanelView(model: app.draftsModel)
                    .frame(minWidth: 360, idealWidth: 420, maxWidth: 560)
            }
        }
    }
}

#Preview {
    MainView()
        .environmentObject(AppState())
}
