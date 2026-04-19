import SwiftUI

struct LibraryView: View {
    @StateObject private var model: LibraryModel

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
        .onAppear {
            if case .idle = model.listState {
                model.refreshList()
            }
        }
    }
}
