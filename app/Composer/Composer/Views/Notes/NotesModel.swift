import AppKit
import Foundation
import SwiftUI

@MainActor
final class NotesModel: ObservableObject {
    enum ListState {
        case idle
        case loading
        case loaded([Note])
        case error(String)
    }

    enum EditorState {
        case empty
        case loading
        case editing(Note, NSAttributedString, String)
        case error(String)

        var originalMarkdown: String? {
            if case .editing(let note, _, _) = self { return note.body } else { return nil }
        }

        var currentMarkdown: String? {
            if case .editing(_, _, let md) = self { return md } else { return nil }
        }
    }

    @Published var listState: ListState = .idle
    @Published var editorState: EditorState = .empty
    /// A load running over content that's already displayed. Views overlay a
    /// delayed indicator rather than blanking the pane.
    @Published private(set) var isListReloading = false
    @Published private(set) var isEditorReloading = false
    @Published var selectedId: String?
    @Published var query: String = ""
    @Published var editorAttributed: NSAttributedString = NSAttributedString(string: "") {
        didSet { handleAttributedChange() }
    }
    @Published var isDirty: Bool = false
    @Published var titleDraft: String = ""
    @Published var pendingDelete: Note?

    private let api: APIClient
    private var autosaveTask: Task<Void, Never>?
    private let autosaveDelay: Duration = .milliseconds(1200)

    init(api: APIClient) {
        self.api = api
    }

    deinit {
        autosaveTask?.cancel()
    }

    /// Keep what's already loaded on screen and flag the reload, rather than
    /// dropping to `.loading` and blanking the pane mid-browse.
    private func beginListLoad() {
        if case .loaded = listState { isListReloading = true } else { listState = .loading }
    }

    private func beginEditorLoad() {
        if case .editing = editorState { isEditorReloading = true } else { editorState = .loading }
    }

    func refreshList() {
        Task { [weak self] in
            guard let self else { return }
            self.beginListLoad()
            do {
                let response = try await self.api.listNotes()
                self.listState = .loaded(response.notes)
            } catch {
                self.listState = .error(error.localizedDescription)
            }
            self.isListReloading = false
        }
    }

    func select(_ id: String?) {
        autosaveTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            if self.isDirty, case .editing = self.editorState {
                await self.saveNow()
            }
            self.selectedId = id
            guard let id else {
                self.editorState = .empty
                self.editorAttributed = NSAttributedString(string: "")
                self.isDirty = false
                self.titleDraft = ""
                self.isEditorReloading = false
                return
            }
            self.beginEditorLoad()
            do {
                let note = try await self.api.getNote(id: id)
                let attributed = MarkdownConverter.attributedString(from: note.body)
                self.editorState = .editing(note, attributed, note.body)
                self.editorAttributed = attributed
                self.titleDraft = note.title ?? ""
                self.isDirty = false
                self.isEditorReloading = false
            } catch {
                self.isEditorReloading = false
                self.editorState = .error(error.localizedDescription)
            }
        }
    }

    func create() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let note = try await self.api.createNote(title: nil, body: "")
                self.refreshList()
                self.select(note.id)
            } catch {
                self.listState = .error(error.localizedDescription)
            }
        }
    }

    func delete(_ note: Note) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.api.deleteNote(id: note.id)
                if self.selectedId == note.id {
                    self.selectedId = nil
                    self.editorState = .empty
                    self.editorAttributed = NSAttributedString(string: "")
                    self.titleDraft = ""
                }
                self.refreshList()
            } catch {
                self.editorState = .error(error.localizedDescription)
            }
        }
    }

    func save() {
        Task { [weak self] in await self?.saveNow() }
    }

    func reloadEditorTypeface() {
        guard case .editing(let note, _, let original) = editorState else { return }
        let markdown = MarkdownConverter.markdown(from: editorAttributed)
        let attributed = MarkdownConverter.attributedString(from: markdown)
        editorAttributed = attributed
        editorState = .editing(note, attributed, original)
    }

    private func saveNow() async {
        guard case .editing(let note, _, _) = editorState else { return }
        let markdown = MarkdownConverter.markdown(from: editorAttributed)
        let title = titleDraft.isEmpty ? nil : titleDraft
        do {
            let updated = try await self.api.patchNote(
                id: note.id,
                title: .some(title),
                body: markdown
            )
            self.editorState = .editing(updated, self.editorAttributed, markdown)
            self.isDirty = false
            self.refreshList()
        } catch {
            self.editorState = .error(error.localizedDescription)
        }
    }

    private func handleAttributedChange() {
        guard case .editing(let note, _, let original) = editorState else { return }
        let current = MarkdownConverter.markdown(from: editorAttributed)
        editorState = .editing(note, editorAttributed, current)
        let titleChanged = titleDraft != (note.title ?? "")
        isDirty = current != original || titleChanged
        if isDirty { scheduleAutosave() }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.autosaveDelay)
            if Task.isCancelled { return }
            if self.isDirty {
                await self.saveNow()
            }
        }
    }

    func titleChanged() {
        guard case .editing(_, _, _) = editorState else { return }
        handleAttributedChange()
    }

    func requestDelete(_ note: Note) {
        pendingDelete = note
    }

    func filteredNotes(_ notes: [Note]) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return notes }
        return notes.filter { note in
            if let t = note.title?.lowercased(), t.contains(q) { return true }
            return note.body.lowercased().contains(q)
        }
    }
}
