import SwiftUI

struct DraftSidePanelView: View {
    @ObservedObject var model: DraftsModel
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .composerSurface(.chrome)
        .onAppear { loadIfReady() }
        .onChange(of: app.backendReady) { _, ready in
            if ready { loadIfReady() }
        }
    }

    private func loadIfReady() {
        guard app.backendReady else { return }
        switch model.listState {
        case .idle, .error: model.refreshList()
        default: break
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Draft").font(.headline)

            if case .loaded(let drafts) = model.listState, !drafts.isEmpty {
                let sorted = sortedDrafts(drafts)
                let recent = Array(sorted.prefix(10))
                Menu {
                    ForEach(recent) { d in
                        Button { model.select(d.id) } label: {
                            Text(title(for: d))
                        }
                    }
                    if sorted.count > recent.count {
                        Divider()
                        Button("Show all in Drafts tab…") {
                            app.selectedTab = .drafts
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Switch draft")
                .accessibilityLabel("Switch draft")
            }

            Spacer()

            Button { model.create() } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Draft")
            .accessibilityLabel("New Draft")

            Button { app.toggleDraftPanel() } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.borderless)
            .help("Hide Draft Panel (⌥⌘D)")
            .accessibilityLabel("Hide Draft Panel")
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
    }

    @ViewBuilder
    private var content: some View {
        switch model.editorState {
        case .empty:
            emptyState
        default:
            DraftEditorView(model: model, isCompact: true)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No current draft", systemImage: "doc.text")
        } description: {
            Text("Start one to compose alongside your reading.")
        } actions: {
            Button { model.create() } label: {
                Label("New Draft", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        // Greedy on purpose — see AskCitationsView.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sortedDrafts(_ drafts: [Draft]) -> [Draft] {
        drafts.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func title(for d: Draft) -> String {
        if let t = d.title, !t.isEmpty { return t }
        let first = d.body.split(separator: "\n").first.map(String.init) ?? ""
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled draft" : trimmed
    }
}
