import SwiftUI

struct DraftsView: View {
    @EnvironmentObject private var app: AppState

    init(api: APIClient) {}

    var body: some View {
        let model = app.draftsModel
        NavigationSplitView {
            DraftsListView(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            DraftEditorView(model: model)
        }
        .focusedSceneValue(\.newItemAction, NewItemAction(title: "New Draft") {
            model.create()
        })
        .focusedSceneValue(\.refreshAction, RefreshAction {
            model.refreshList()
        })
        .onAppear {
            loadIfReady(model)
            consumePending()
        }
        .onChange(of: app.backendReady) { _, ready in
            if ready { loadIfReady(model) }
        }
        .onChange(of: app.pendingDraftSelection) { _, _ in
            consumePending()
        }
    }

    private func loadIfReady(_ model: DraftsModel) {
        guard app.backendReady else { return }
        switch model.listState {
        case .idle, .error: model.refreshList()
        default: break
        }
    }

    private func consumePending() {
        guard let id = app.pendingDraftSelection else { return }
        app.pendingDraftSelection = nil
        app.draftsModel.refreshList()
        app.draftsModel.select(id)
    }
}
