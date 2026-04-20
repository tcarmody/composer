import AppKit
import Foundation
import SwiftUI

@MainActor
final class DraftsModel: ObservableObject {
    enum ListState {
        case idle
        case loading
        case loaded([Draft])
        case error(String)
    }

    enum EditorState {
        case empty
        case loading
        case editing(Draft, NSAttributedString, String)
        case error(String)

        var originalMarkdown: String? {
            if case .editing(let draft, _, _) = self { return draft.body } else { return nil }
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
    @Published var statusDraft: DraftStatus = .wip

    private let api: APIClient
    private var autosaveTask: Task<Void, Never>?
    private let autosaveDelay: Duration = .milliseconds(1200)

    init(api: APIClient) {
        self.api = api
    }

    deinit {
        autosaveTask?.cancel()
    }

    func refreshList() {
        Task { [weak self] in
            guard let self else { return }
            self.listState = .loading
            do {
                let response = try await self.api.listDrafts()
                self.listState = .loaded(response.drafts)
            } catch {
                self.listState = .error(error.localizedDescription)
            }
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
                self.statusDraft = .wip
                return
            }
            self.editorState = .loading
            do {
                let draft = try await self.api.getDraft(id: id)
                let attributed = MarkdownConverter.attributedString(from: draft.body)
                self.editorState = .editing(draft, attributed, draft.body)
                self.editorAttributed = attributed
                self.titleDraft = draft.title ?? ""
                self.statusDraft = draft.status
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
                let draft = try await self.api.createDraft(title: nil, body: "", status: .wip)
                self.refreshList()
                self.select(draft.id)
            } catch {
                self.listState = .error(error.localizedDescription)
            }
        }
    }

    func delete(_ draft: Draft) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.api.deleteDraft(id: draft.id)
                if self.selectedId == draft.id {
                    self.selectedId = nil
                    self.editorState = .empty
                    self.editorAttributed = NSAttributedString(string: "")
                    self.titleDraft = ""
                    self.statusDraft = .wip
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

    private func saveNow() async {
        guard case .editing(let draft, _, _) = editorState else { return }
        let markdown = MarkdownConverter.markdown(from: editorAttributed)
        let title = titleDraft.isEmpty ? nil : titleDraft
        do {
            let updated = try await self.api.patchDraft(
                id: draft.id,
                title: .some(title),
                body: markdown,
                status: statusDraft
            )
            self.editorState = .editing(updated, self.editorAttributed, markdown)
            self.isDirty = false
            self.refreshList()
        } catch {
            self.editorState = .error(error.localizedDescription)
        }
    }

    private func handleAttributedChange() {
        guard case .editing(let draft, _, let original) = editorState else { return }
        let current = MarkdownConverter.markdown(from: editorAttributed)
        editorState = .editing(draft, editorAttributed, current)
        let titleChanged = titleDraft != (draft.title ?? "")
        let statusChanged = statusDraft != draft.status
        isDirty = current != original || titleChanged || statusChanged
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

    func statusChanged() {
        guard case .editing(_, _, _) = editorState else { return }
        handleAttributedChange()
    }
}
