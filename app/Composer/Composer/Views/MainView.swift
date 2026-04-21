import SwiftUI

struct MainView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
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
            }
        }
    }
}

#Preview {
    MainView()
        .environmentObject(AppState())
}
