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
            if case .idle = model.listState {
                model.refreshList()
            }
            consumePending()
        }
        .onChange(of: app.pendingDraftSelection) { _, _ in
            consumePending()
        }
    }

    private func consumePending() {
        guard let id = app.pendingDraftSelection else { return }
        app.pendingDraftSelection = nil
        app.draftsModel.refreshList()
        app.draftsModel.select(id)
    }
}
