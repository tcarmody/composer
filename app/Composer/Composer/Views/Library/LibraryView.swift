import SwiftUI

struct LibraryView: View {
    @StateObject private var model: LibraryModel
    @EnvironmentObject private var app: AppState

    enum Scope: Hashable { case active, archived }
    @State private var scope: Scope = .active

    init(api: APIClient) {
        _model = StateObject(wrappedValue: LibraryModel(api: api))
    }

    var body: some View {
        NavigationSplitView {
            ItemListView(model: model)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            ItemDetailView(model: model)
        }
        .searchable(text: $model.query, prompt: "Search items")
        .searchScopes($scope, activation: .onSearchPresentation) {
            Text("Active").tag(Scope.active)
            Text("Archived").tag(Scope.archived)
        }
        .onChange(of: model.query) { _, _ in
            model.scheduleSearch()
        }
        .onChange(of: scope) { _, newValue in
            model.showArchived = (newValue == .archived)
            model.refreshList()
        }
        .focusedSceneValue(\.refreshAction, RefreshAction {
            model.refreshList()
        })
        .focusedSceneValue(\.archiveAction, currentArchiveAction)
        .onAppear {
            loadIfReady()
            consumePending()
        }
        .onChange(of: app.backendReady) { _, ready in
            if ready { loadIfReady() }
        }
        .onChange(of: app.pendingItemSelection) { _, _ in
            consumePending()
        }
    }

    private var currentArchiveAction: ArchiveAction? {
        guard case .loaded(let item) = model.detailState else { return nil }
        return ArchiveAction(
            title: item.isArchived ? "Unarchive Item" : "Archive Item",
            perform: { model.toggleArchive(item) }
        )
    }

    private func loadIfReady() {
        guard app.backendReady else { return }
        switch model.listState {
        case .idle, .error: model.refreshList()
        default: break
        }
    }

    private func consumePending() {
        guard let id = app.pendingItemSelection else { return }
        app.pendingItemSelection = nil
        model.refreshList()
        model.select(id)
    }
}
