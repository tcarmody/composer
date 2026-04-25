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
        .onAppear {
            if case .idle = model.listState {
                model.refreshList()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
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
            }

            Spacer()

            Button { model.create() } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Draft")

            Button { app.toggleDraftPanel() } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.borderless)
            .help("Hide Draft Panel (⌥⌘D)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No current draft").font(.headline)
            Text("Start one to compose alongside your reading.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { model.create() } label: {
                Label("New Draft", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
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
