import SwiftUI

struct CollectionsView: View {
    @StateObject private var model: CollectionsModel
    @EnvironmentObject private var app: AppState

    init(api: APIClient) {
        _model = StateObject(wrappedValue: CollectionsModel(api: api))
    }

    var body: some View {
        NavigationSplitView {
            CollectionsListView(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            CollectionDetailView(model: model)
        }
        .searchable(text: $model.query, prompt: "Search collections")
        .focusedSceneValue(\.newItemAction, NewItemAction(title: "New Collection") {
            model.isCreating = true
        })
        .focusedSceneValue(\.refreshAction, RefreshAction {
            model.refreshList()
        })
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
}
