import SwiftUI

struct MainView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @AppStorage("draftPanelWidth") private var draftPanelWidth: Double = 420

    private var panelVisible: Bool {
        app.isDraftPanelVisible && app.selectedTab != .drafts
    }

    var body: some View {
        // safeAreaInset rather than a VStack sibling: the banner becomes part
        // of the window's safe area, so the split view below keeps its own
        // layout and the bar can animate in and out instead of being spliced
        // into the view tree.
        mainSplit
            .safeAreaInset(edge: .top, spacing: 0) {
                if app.backendStale {
                    staleBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: app.backendStale)
            .onChange(of: app.selectedTab) { _, _ in
                if app.draftsModel.isDirty { app.draftsModel.save() }
            }
    }

    private var staleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(StatusTone.caution.accent)
                .accessibilityHidden(true)
            Text("Backend is running older code than this app. Restart it to pick up the latest.")
                .font(.callout)
            Spacer(minLength: 8)
            Button("Restart Backend") {
                app.supervisor.restart()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        // A flat yellow wash went murky olive under the dark palettes and left
        // the label at whatever contrast happened to fall out. The bar
        // material carries the appearance; the tone is a wash on top of it.
        .background {
            StatusTone.caution.fill(scheme).background(.bar)
        }
        .overlay(alignment: .bottom) { Divider() }
        // Deliberately not `children: .combine` — that folds the button into
        // one element and VoiceOver loses the only way to act on the warning.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Backend out of date")
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
