import SwiftUI

struct NotesView: View {
    @StateObject private var model: NotesModel

    init(api: APIClient) {
        _model = StateObject(wrappedValue: NotesModel(api: api))
    }

    var body: some View {
        NavigationSplitView {
            NotesListView(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            NoteEditorView(model: model)
        }
        .onAppear {
            if case .idle = model.listState {
                model.refreshList()
            }
        }
    }
}
