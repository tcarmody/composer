import Foundation
import SwiftUI

@MainActor
final class CollectionsModel: ObservableObject {
    enum ListState {
        case idle
        case loading
        case loaded([Collection])
        case error(String)
    }

    enum DetailState {
        case empty
        case loading
        case loaded(Outline)
        case error(String)
    }

    @Published var listState: ListState = .idle
    @Published var detailState: DetailState = .empty
    @Published var selectedId: String?

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func refreshList() {
        Task { [weak self] in
            guard let self else { return }
            self.listState = .loading
            do {
                let collections = try await self.api.listCollections()
                self.listState = .loaded(collections)
            } catch {
                self.listState = .error(error.localizedDescription)
            }
        }
    }

    func select(_ id: String?) {
        selectedId = id
        guard let id else {
            detailState = .empty
            return
        }
        loadDetail(id: id)
    }

    func loadDetail(id: String) {
        Task { [weak self] in
            guard let self else { return }
            self.detailState = .loading
            do {
                let outline = try await self.api.getCollection(id: id)
                self.detailState = .loaded(outline)
            } catch {
                self.detailState = .error(error.localizedDescription)
            }
        }
    }

    func create(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let created = try await self.api.createCollection(name: trimmed)
                self.refreshList()
                self.select(created.id)
            } catch {
                self.listState = .error(error.localizedDescription)
            }
        }
    }

    func delete(_ collection: Collection) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.api.deleteCollection(id: collection.id)
                self.selectedId = nil
                self.detailState = .empty
                self.refreshList()
            } catch {
                self.detailState = .error(error.localizedDescription)
            }
        }
    }

    func removeMember(_ node: OutlineNode) {
        guard let id = selectedId else { return }
        applyOptimisticRemove(node)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.api.removeCollectionMember(
                    id: id, memberType: node.memberType, memberId: node.memberId)
                self.loadDetail(id: id)
                self.refreshList()
            } catch {
                self.detailState = .error(error.localizedDescription)
            }
        }
    }

    func reorder(from source: IndexSet, to destination: Int) {
        guard case .loaded(var outline) = detailState,
              let id = selectedId else { return }
        var next = outline.members
        next.move(fromOffsets: source, toOffset: destination)
        outline = Outline(collection: outline.collection, members: next)
        detailState = .loaded(outline)

        let ordered = next.map { ($0.memberType, $0.memberId) }
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await self.api.reorderCollection(id: id, members: ordered)
                self.detailState = .loaded(updated)
            } catch {
                self.loadDetail(id: id)
            }
        }
    }

    func addInlineNote(body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = selectedId else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await self.api.createInlineNote(collectionId: id, body: trimmed)
                self.detailState = .loaded(updated)
                self.refreshList()
            } catch {
                self.detailState = .error(error.localizedDescription)
            }
        }
    }

    private func applyOptimisticRemove(_ node: OutlineNode) {
        guard case .loaded(let outline) = detailState else { return }
        let remaining = outline.members.filter { $0.id != node.id }
        detailState = .loaded(Outline(collection: outline.collection, members: remaining))
    }
}
