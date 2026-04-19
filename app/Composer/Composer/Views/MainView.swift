import SwiftUI

struct MainView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HealthBadge(status: app.health)
            }
        }
    }

    private var sidebar: some View {
        List(selection: $app.selectedTab) {
            Section("Composer") {
                ForEach(NavTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch app.selectedTab {
        case .library:
            LibraryPlaceholder()
        case .collections:
            CollectionsPlaceholder()
        }
    }
}

private struct LibraryPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Library",
            systemImage: "tray.full",
            description: Text("Items promoted from DataPoints will appear here.")
        )
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
