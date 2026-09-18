import SwiftUI

struct MainView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @AppStorage("draftPanelWidth") private var draftPanelWidth: Double = 420

    private var panelVisible: Bool {
        app.isDraftPanelVisible && app.selectedTab != .drafts
    }

    var body: some View {
        // A VStack sibling, not safeAreaInset. The inset reads as the tidier
        // option, but HSplitView's children don't honor it: the list's section
        // header and the detail pane's action row both slide under the bar and
        // get clipped. Stacking costs the banner nothing and keeps the split
        // view's own layout intact.
        VStack(spacing: 0) {
            if app.backendStale {
                staleBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            mainSplit
        }
        .animation(.easeInOut(duration: 0.2), value: app.backendStale)
        .onChange(of: app.selectedTab) { _, _ in
            if app.draftsModel.isDirty { app.draftsModel.save() }
        }
    }

    private var staleBanner: some View {
        HStack(spacing: Spacing.small) {
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
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .frame(maxWidth: .infinity)
        // A flat yellow wash went murky olive under the dark palettes and left
        // the label at whatever contrast happened to fall out. The bar
        // material carries the appearance; the tone is a wash on top of it.
        .background {
            StatusTone.caution.fill(scheme).background(.bar)
        }
        .overlay(alignment: .bottom) {
            // macOS 26 draws its own scroll edge effect where content meets
            // chrome; a manual hairline competes with it. Older systems still
            // want the separator.
            if #unavailable(macOS 26) { Divider() }
        }
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
                    .frame(maxHeight: .infinity)
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
        // HSplitView sizes to its content. Tabs whose body is greedy (the
        // lists) filled the window anyway; Ask, whose transcript collapses to
        // an empty state, left the split centered with dead space above and
        // below — and pushed the banner down off the top edge with it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MainView()
        .environmentObject(AppState())
}
