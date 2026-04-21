import SwiftUI

struct NotesView: View {
    @StateObject private var model: NotesModel
    @EnvironmentObject private var app: AppState

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
        .focusedSceneValue(\.newItemAction, NewItemAction(title: "New Note") {
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
        .onChange(of: app.pendingNoteSelection) { _, _ in
            consumePending()
        }
    }

    private func consumePending() {
        guard let id = app.pendingNoteSelection else { return }
        app.pendingNoteSelection = nil
        model.refreshList()
        model.select(id)
    }
}
