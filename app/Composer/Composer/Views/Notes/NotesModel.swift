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
    @Published var selectedId: String?
    @Published var editorAttributed: NSAttributedString = NSAttributedString(string: "") {
        didSet { handleAttributedChange() }
    }
    @Published var isDirty: Bool = false
    @Published var titleDraft: String = ""

    private let api: APIClient
    private var saveTask: Task<Void, Never>?

    init(api: APIClient) {
        self.api = api
    }

    func refreshList() {
        Task { [weak self] in
            guard let self else { return }
            self.listState = .loading
            do {
                let response = try await self.api.listNotes()
                self.listState = .loaded(response.notes)
            } catch {
                self.listState = .error(error.localizedDescription)
            }
        }
    }

    func select(_ id: String?) {
        selectedId = id
        guard let id else {
            editorState = .empty
            editorAttributed = NSAttributedString(string: "")
            isDirty = false
            titleDraft = ""
            return
        }
        Task { [weak self] in
            guard let self else { return }
            self.editorState = .loading
            do {
                let note = try await self.api.getNote(id: id)
                let attributed = MarkdownConverter.attributedString(from: note.body)
                self.editorState = .editing(note, attributed, note.body)
                self.editorAttributed = attributed
                self.titleDraft = note.title ?? ""
                self.isDirty = false
            } catch {
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
        guard case .editing(let note, _, _) = editorState else { return }
        let markdown = MarkdownConverter.markdown(from: editorAttributed)
        let title = titleDraft.isEmpty ? nil : titleDraft
        Task { [weak self] in
            guard let self else { return }
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
    }

    private func handleAttributedChange() {
        guard case .editing(let note, _, let original) = editorState else { return }
        let current = MarkdownConverter.markdown(from: editorAttributed)
        editorState = .editing(note, editorAttributed, current)
        let titleChanged = titleDraft != (note.title ?? "")
        isDirty = current != original || titleChanged
    }

    func titleChanged() {
        guard case .editing(_, _, _) = editorState else { return }
        handleAttributedChange()
    }
}
