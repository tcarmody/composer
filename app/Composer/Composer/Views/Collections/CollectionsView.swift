import SwiftUI

struct CollectionsView: View {
    @StateObject private var model: CollectionsModel

    init(api: APIClient) {
        _model = StateObject(wrappedValue: CollectionsModel(api: api))
    }

    @State private var showNewPrompt = false

    var body: some View {
        NavigationSplitView {
            CollectionsListView(model: model, externalShowNew: $showNewPrompt)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            CollectionDetailView(model: model)
        }
        .focusedSceneValue(\.newItemAction, NewItemAction(title: "New Collection") {
            showNewPrompt = true
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
