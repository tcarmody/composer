import SwiftUI

struct CollectionsView: View {
    @StateObject private var model: CollectionsModel

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
        .onAppear {
            if case .idle = model.listState {
                model.refreshList()
            }
        }
    }
}
