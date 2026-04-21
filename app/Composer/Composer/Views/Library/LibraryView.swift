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
            if case .idle = model.listState {
                model.refreshList()
            }
            consumePending()
        }
        .onChange(of: app.pendingItemSelection) { _, _ in
            consumePending()
        }
    }

    private func consumePending() {
        guard let id = app.pendingItemSelection else { return }
        app.pendingItemSelection = nil
        model.refreshList()
        model.select(id)
    }
}
