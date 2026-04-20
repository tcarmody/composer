import SwiftUI

struct DraftsView: View {
    @StateObject private var model: DraftsModel

    init(api: APIClient) {
        _model = StateObject(wrappedValue: DraftsModel(api: api))
    }

    var body: some View {
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
        }
    }
}
