import SwiftUI

struct LibraryView: View {
    @StateObject private var model: LibraryModel
    @EnvironmentObject private var app: AppState

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
        .focusedSceneValue(\.refreshAction, RefreshAction {
            model.refreshList()
        })
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
