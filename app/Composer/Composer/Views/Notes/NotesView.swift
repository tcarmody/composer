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
            loadIfReady()
            consumePending()
        }
        .onChange(of: app.backendReady) { _, ready in
            if ready { loadIfReady() }
        }
        .onChange(of: app.pendingNoteSelection) { _, _ in
            consumePending()
        }
        .onChange(of: app.typeface) { _, _ in
            model.reloadEditorTypeface()
        }
    }

    private func loadIfReady() {
        guard app.backendReady else { return }
        switch model.listState {
        case .idle, .error: model.refreshList()
        default: break
        }
    }

    private func consumePending() {
        guard let id = app.pendingNoteSelection else { return }
        app.pendingNoteSelection = nil
        model.refreshList()
        model.select(id)
    }
}
