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
                    CollectionsPlaceholder()
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

private struct CollectionsPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Collections",
            systemImage: "rectangle.stack",
            description: Text("Gather items and notes into collections.")
        )
    }
}

#Preview {
    MainView()
        .environmentObject(AppState())
}
